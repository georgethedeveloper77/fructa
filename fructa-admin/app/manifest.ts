import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Fructa — Kenyan rates terminal',
    short_name: 'Fructa',
    description:
      'Every live rate in Kenya — money market funds, T-bills, bonds, SACCOs and insurance — ranked and compared.',
    start_url: '/',
    display: 'standalone',
    background_color: '#060709',
    theme_color: '#060709',
    icons: [
      { src: '/icon.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
      { src: '/apple-icon.png', sizes: '180x180', type: 'image/png' },
    ],
  };
}
