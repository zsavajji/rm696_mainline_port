---
layout: home

hero:
  name: Linux 6.18 for the Nokia N9
  text: Stock Harmattan, unmodified, on a current kernel
  tagline: Linux 6.18.55 with the drivers and interfaces Harmattan PR1.3 expects, so the phone's own closed userspace runs as it did on Nokia's 2.6.32.
  actions:
    - theme: brand
      text: Install
      link: /install
    - theme: alt
      text: Build it yourself
      link: /build
    - theme: alt
      text: What works
      link: /status

features:
  - title: Harmattan as it ships
    details: No file of the phone's root filesystem is changed. Every difference between 6.18 and Nokia's kernel is handled in the kernel, at the device names, sysfs paths and ioctls Harmattan uses.
  - title: The original GPU stack
    details: Harmattan's closed PowerVR SGX libraries (DDK 1.4.14.2514) run on a forward-ported kernel driver with the same interface, so X, GLES2 and the compositor work as on stock.
  - title: The whole phone
    details: Display, GPU, DSP video decoding, both cameras, audio, WLAN, Bluetooth, FM radio, NFC, TV-out, sensors, charging and the modem link, with CORE retention and OFF in standby.
  - title: A rescue SSH server
    details: The image starts a root SSH server on the USB cable before Harmattan, with the phone's own keys, so the phone stays reachable even when Harmattan doesn't come up.
---
