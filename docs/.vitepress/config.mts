import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'N9 on Linux 6.18',
  description: 'Linux 6.18 for the Nokia N9, running stock Harmattan PR1.3 unmodified',
  base: '/rm696_mainline_port/',   // served at https://zsavajji.github.io/rm696_mainline_port/
  cleanUrls: true,
  lastUpdated: true,
  themeConfig: {
    nav: [
      { text: 'Install', link: '/install' },
      { text: 'Build', link: '/build' },
      { text: 'Kernel', link: '/kernel' },
    ],
    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'Status', link: '/status' },
          { text: 'Install', link: '/install' },
          { text: 'Rescue SSH', link: '/rescue' },
          { text: 'Build', link: '/build' },
        ],
      },
      {
        text: 'Hardware',
        items: [
          { text: 'Display', link: '/display' },
          { text: 'GPU', link: '/gpu' },
          { text: 'TV-out', link: '/tv-out' },
          { text: 'Cameras', link: '/camera' },
          { text: 'DSP and video', link: '/dsp' },
          { text: 'Audio', link: '/audio' },
          { text: 'Bluetooth', link: '/bluetooth' },
          { text: 'FM radio', link: '/fm' },
          { text: 'NFC', link: '/nfc' },
          { text: 'Modem and BB5', link: '/modem' },
        ],
      },
      {
        text: 'Power and speed',
        items: [
          { text: 'Power', link: '/power' },
          { text: 'Performance', link: '/performance' },
        ],
      },
      {
        text: 'Reference',
        items: [
          { text: 'The kernel', link: '/kernel' },
          { text: 'Removed and switched off', link: '/removed' },
          { text: 'Firmware', link: '/firmware' },
        ],
      },
    ],
    search: { provider: 'local' },
    outline: [2, 3],
  },
})
