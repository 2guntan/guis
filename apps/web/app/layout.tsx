import type { Metadata, Viewport } from 'next';
import localFont from 'next/font/local';
import './globals.css';

// Polices embarquées (sous-ensemble latin, licence OFL dans app/fonts) : aucun appel à Google au build ni à l'usage.
const display = localFont({ src: './fonts/Fraunces-var.woff2', variable: '--font-display', weight: '100 900', display: 'swap' });
const body = localFont({ src: './fonts/Geist-var.woff2', variable: '--font-body', weight: '100 900', display: 'swap' });

export const metadata: Metadata = {
  title: { default: 'Guis', template: '%s · Guis' },
  description: 'Collecte et suivi satellite des champs.',
  icons: { icon: '/icon.svg' },
};

export const viewport: Viewport = { themeColor: '#1F4D3A', width: 'device-width', initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr" className={`${display.variable} ${body.variable}`}>
      <body className="min-h-dvh">{children}</body>
    </html>
  );
}
