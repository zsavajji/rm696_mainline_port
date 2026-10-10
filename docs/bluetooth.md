# Bluetooth

Bluetooth works as it does on stock. Harmattan's bluetoothd (BlueZ 4) drives the TI WL1273's Bluetooth
core through mainline's `hci_nokia`, at stock's 3.69 Mbaud. OBEX file transfers work both ways, and
with Bluetooth on, the UART and the CORE power domain still idle, down to CORE OFF. Profiles other than
OBEX (A2DP, HFP/HSP, PAN, DUN) and calls through a Bluetooth headset have not been tried yet.

## Hardware and driver

| | |
|---|---|
| Chip | the Bluetooth core of the TI WL1273 (TI1273 firmware); the chip has its own Nokia BD address |
| Host link | UART2 (`4806c000.serial`, 8250_omap), Nokia's H4 variant, hardware flow control, PIO (no DMA) |
| GPIOs | reset 26, host wakeup 101 (chip to SoC), Bluetooth wakeup 37 (SoC to chip) |
| Driver | mainline's `hci_nokia` on serdev (device `serial0-0`, driver `nokia-bluetooth`), a module that udev loads once Harmattan's root is up, as stock loaded Nokia's `hci_h4p` |
| Stack | built in: the Bluetooth core, RFCOMM, BNEP, HIDP, for bluetoothd (raw HCI and ioctls, no mgmt) |
| Audio | SCO over PCM on McBSP4, through the third ALSA card `dfl61wl1273` ([below](#headset-audio-sco)) |

The firmware is Nokia's and stays on the phone: `hci_nokia` picks it by chip version as `hci_h4p` did
(0xd1/0xf1: `ti1273_le.bin`, this N9's; 0xe1: `ti1273_prele.bin`; others: `ti1273.bin`) and asks for it
under stock's names in Harmattan's `/lib/firmware` (see [Firmware](./firmware)). With the wrong file the
chip never answers the HCI reset. The set-up (reset, speed negotiation, firmware) runs again at every
power-on, as on stock, because the chip is held in reset while Bluetooth is off.

## What the kernel changes

| Commit | What and why |
|---|---|
| 83a78072e `hci_nokia: load stock TI1273 firmware by chip version` | the right firmware per chip; the LE firmware answers LE Read Supported States with 4 of 8 bytes, which failed the whole init (`HCI_QUIRK_BROKEN_LE_STATES`) |
| b0eb20e80 `hci_nokia: the TI1273 firmware at stock's names` | the phone's own files, no links |
| 24267529d `Bluetooth: accept BT_SECURITY with the level alone (BlueZ 4)` | since 6.9 the kernel wanted the whole struct; BlueZ 4's short form got EINVAL, so no RFCOMM/DUN servers |
| 3a56aa7af `Bluetooth: keep the scan mode a stack without mgmt writes` | 6.18 rewrites the scan mode after every connection from flags only mgmt sets; BlueZ 4 writes it raw, so after one connection the N9 stopped being connectable |
| 816cac692 `serial: 8250_omap: keep automatic RTS when flow control comes after RTS` | 8250_omap enabled auto-RTS only if RTS was raised after flow control; `hci_nokia` does it the other way round, so the receive FIFO overran |
| 7be81a7b1 `hci_nokia: drop stalled frames and stray bytes on receive` | H4 has no resync: a frame started on a corrupt byte swallowed every later frame, across power cycles. A frame still incomplete 500 ms after its last byte is dropped; a stray byte between packets is dropped alone, as `hci_h4p` |
| 9378f210e `hci_nokia: flow control off before the chip goes into reset` | a chip in reset holds CTS (pulled up), so queued bytes stuck in the TX FIFO and every close waited 30 s |
| f96b15a50 `serial: 8250: drop the TX runtime PM reference at shutdown` | a mainline bug: with bytes left in the FIFO at shutdown the UART stayed awake for the rest of the boot |
| cc413cc8f, 40900cbd7 `RTS down while the chip sleeps, RTS alone`; `release the UART while the chip sleeps` | UART2 and CORE idle with Bluetooth on ([Power](#power)) |
| 828c50ecb `hci_nokia: let a transmission end before the power-off` | a write still waiting for the UART across a power-off and the next power-on dropped a runtime PM reference twice ("Runtime PM usage count underflow!"); the shutdown flushes the write work |
| ab9ec256d `hci_nokia: end a transmission from a timer, as Nokia's hci_h4p` | upstream waited ~22 ms for the UART after every burst, halving throughput; a 100 ms timer ends a transmission as stock's `lazy_release` did |
| cc5876990 `serial: 8250_omap: raise RTS after the EFR write when autoRTS is on` | a mainline bug that corrupted received data at 3.69 Mbaud ([Gotchas](#gotchas)) |
| d57e894fd, 1e10a8a2b `ti_baud`; `the TI1271 at 3.69 Mbaud, as Nokia's hci_h4p` | stock's rate (upstream switched the chip to 921600) |
| ccfc3678b `hci_nokia: forget a frame cut short at power-off` | a partial frame survived a power cycle and ate the next negotiation reply ("Negotiation failed: -110") |
| 7370c84d8 `tty: serdev: ignore breaks` | a break doesn't reach the H4 parser as a zero byte |

UART2 runs without DMA (`/delete-property/ dmas` in `omap3-n9-nokia.dtsi`): through RX DMA, bytes skip
the per-character line-status check and received bursts came out garbled.

## Speed

`ti_baud` (a `hci_nokia` module parameter, default 3692300) sets the rate at the next power-on;
`ti_baud=921600` is the old upstream rate. Loopback throughput (`tests/btloop.pl`, the controller
echoing ACL packets, each checked byte for byte), KB/s each way:

| Packets in flight | 1 | 3 | 16 |
|---|---|---|---|
| 921600 baud | 34.9 | 70.2 | 69.1 |
| 3.69 Mbaud | 99.3 | 225.3 | 225.8 |

At 3.69 Mbaud: 95 inquiries, 160 spaced commands, 15 power cycles, loopback with the chip sleeping
between packets, and 43 SDP browses of a nearby computer, with 0 receive or line errors. OBEX send and
receive with an Android phone work. The speed of a real file transfer hasn't been measured.

## Power

Stock's `hci_h4p` gated the UART's clocks between the chip's bursts. Here:

- **Bluetooth off**: `hci_nokia` sets `HCI_QUIRK_NON_PERSISTENT_SETUP`, so the serdev port is closed,
  the chip is held in reset with its wakeup line low, and UART2 is runtime-suspended.
- **Bluetooth on, chip asleep**: RTS goes down and the serdev controller's runtime PM reference is
  dropped, so UART2 suspends and drops its 555 µs CPU latency request. On host wakeup (GPIO 101) the
  UART is resumed first (which clears its FIFOs) and RTS is raised after it. The chip waits for RTS
  before it sends, so nothing is lost even with RTS raised 20 ms late (`rts_delay_us`, a test knob).
- **CORE retention**: unplugged with the display off, CORE retains as often with Bluetooth on as
  with it off.
- **CORE OFF**: with an inquiry every 20 s through CORE OFF, every inquiry completed with 0 HCI or UART
  errors. The chip wakes the SoC from OFF through GPIO 101's pad (its wake bit is set as NOLO sets it),
  and RTS is down before UART2 is released, so the chip waits through the wakeup. Like stock, the
  UART pads have no OFF-mode values, and none are needed. See [Power](./power).

## Headset audio (SCO)

As on stock, SCO goes over PCM, not HCI. The chip's PCM is wired to McBSP4, which NOLO muxes on the GPMC
nCS4-7 pads. The third card, `dfl61wl1273`, runs on Nokia's WL1273 codec, which it shares with the
[FM radio](./fm). The codec stays in BT mode by default: DSP_A, 8 kHz mono, the chip as master (Nokia's
firmware sets up the chip's PCM side itself). Harmattan's PulseAudio has `sink.hw1`/`source.hw1` on it,
and streams to it work. A call through a Bluetooth headset hasn't been tried.

McSPI1, 3 and 4 are disabled in the DT (unused on the N9; the vibra is on McSPI2). Each McSPI takes two
sDMA channels per chip select at probe, and with all four enabled McBSP4 got none ("Missing dma channel
for stream").

## Checking it

As root on the phone:

```sh
hciconfig hci0                         # UP RUNNING; "errors:" on the RX and TX lines stay 0
hcitool inq --flush                    # without --flush, hcitool answers from the inquiry cache
grep '^1:' /proc/tty/driver/serial     # UART2; fe/pe/brk/oe appear only when nonzero
cat /sys/bus/platform/devices/4806c000.serial/power/runtime_status   # suspended when idle
od -An -td4 -N4 /dev/cpu_dma_latency   # 555 while UART2 is active
dmesg | grep -i "nokia\|hci0\|Frame reassembly"
```

`/proc/tty/driver/serial` and `hciconfig` count from boot, so take a baseline before a test.

## Gotchas

- **LCR 0xbf is a frame format too.** 8250_omap reaches the EFR (auto-RTS) through configuration mode B,
  LCR 0xbf, which is also *parity on, two stop bits*. Mainline raised RTS before that access. The chip,
  waiting for RTS with data ready, starts at once, and at 3.69 Mbaud (2.7 µs a character) its first
  character falls inside the window: a framing and parity error (a `pe` count on an 8N1 line means this),
  then misframed bytes, "Frame reassembly failed", corrupt ACL headers. At 921600 the window ends inside
  the character. RTS now goes up after the EFR write, as `hci_h4p` did (cc5876990).
- **On OMAP3 every termios change clears the receive FIFO** (8250_omap's MDR1 erratum path). Upstream
  `hci_nokia`'s resume raised RTS and then set flow control, and the chip's first bytes were already in
  the FIFO: an event that arrived as `01 00` instead of `04 01 01 00`. Toggle RTS alone
  (`serdev_device_set_rts()`), never flow control, while the chip may send.
- **The "zeros" are EIR padding, not line noise.** An Extended Inquiry Result carries 240 bytes of
  zero-padded EIR. Once its first bytes are lost the rest looks like garbage, and its body parses as an
  ACL header.
- **Loopback proves nothing about the chip's wakeups**, because a looped-back chip never sleeps.
  `btloop.pl`'s `GAP=` makes it sleep between packets.
- **bluetoothd interferes with raw tests.** It cancels a raw `hcitool inq` while it sets the adapter up
  after `hciconfig up` (wait about 10 s), and powers the adapter back on within seconds of a
  `hciconfig hci0 down`. Pause it (`kill -STOP`, later `-CONT`) for user-channel tests.
- **A stuck inquiry blocks every later one.** Clear it with `hcitool cmd 0x01 0x0002` (Inquiry Cancel)
  or `hciconfig hci0 down; hciconfig hci0 up`.
- **A failed power-on at probe leaves `HCI_SETUP` set for the whole boot**, and the HCI user channel then
  refuses with EBUSY. Re-probe the driver:
  `echo serial0-0 > /sys/bus/serial/drivers/nokia-bluetooth/unbind`, then the same to `bind`.
- `rx_dump=1` (a temporary `hci_nokia` parameter) logs every received chunk. Inquiry results and ACL
  data carry other people's addresses and file contents, so don't share that log.

## Not done

- A2DP, HFP/HSP, PAN, DUN and a call through a Bluetooth headset: they need a paired device.
- An OBEX transfer during CORE OFF (CORE OFF itself was tested with inquiries).
- Seen once each, not reproduced: a firmware command timeout and a chip "hardware error 0x23" while
  bluetoothd started during a power-off stress test, and power-offs taking 0.5-5 s instead of about
  20 ms. Power-offs that race queued commands still log a few stray bytes at the cut; the next set-up is
  clean.
