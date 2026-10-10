# Rescue SSH

The release's initramfs starts its own SSH server (dropbear) as soon as Harmattan's root filesystem
is mounted, before Harmattan itself starts. If Harmattan doesn't come up, or its USB modes or its own
SSH server don't, the phone is still reachable over the USB cable.

```sh
ssh -p 2222 root@192.168.2.15
```

You land in the initramfs's shell (BusyBox), with Harmattan's root filesystem at `/newroot`.
`chroot /newroot` gives you Harmattan's own tools.

## The network

- At boot the initramfs brings up a USB network that presents itself as Harmattan's SDK mode does
  (USB id `0421:0519`, "Nokia N9 RNDIS/Ethernet"). The phone is `192.168.2.15`; give your computer's
  side `192.168.2.14/24`, as for SDK mode. Its MAC addresses are derived from the eMMC, so they stay the
  same on every boot of the same phone.
- When Harmattan's `usb_moded` loads a USB mode (any of them), the rescue network steps aside for it.
  In SDK mode the phone keeps `192.168.2.15` and the rescue server keeps listening on it, next to
  Harmattan's own SSH server on port 22.
- The server listens on the USB address only: never on WLAN.

## Keys and passwords

- **Keys**: the phone's own `/root/.ssh/authorized_keys` (ed25519, RSA or ECDSA), read at every login:
  add or remove a key there and it applies at once. With no key there, nobody gets in. The image carries
  no key and no password.
- **Password (opt-in)**: create `/root/.ssh/dropbear-password` (as root: `touch`) and root's own
  Harmattan password works too, as it is at boot. Never the factory one: while root's password is still
  `rootme`, the server stays key-only. Change it with `passwd` as root.
- The server's host key is made at the first boot and kept in `/var/lib/n9-618/`.

## Phones without a working power button

On a phone whose power button doesn't work, a real power-off can be hard to come back from. Create
`/var/lib/n9-618/poweroff-halt` (as root) and a power-off halts the phone instead, with the watchdogs
left running, so it resets and boots again after a while instead of staying off.

## Crash records

A kernel panic reboots the phone after 10 s. The last 256 KiB of the kernel's log and the panic's
record survive the reset in RAM, and at the next boot of this kernel the initramfs saves them to
`/var/lib/n9-618/pstore/<date>/`. (After a RAM boot the next boot is the flashed kernel, unless 0xFFFF
is waiting again, and the record is lost.)

If Harmattan's root filesystem doesn't mount at all, the initramfs reboots after 10 s, as Nokia's
kernel did.
