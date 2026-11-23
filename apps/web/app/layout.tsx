import type { Metadata, Viewport } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: { default: 'Guis', template: '%s · Guis' },
  description: 'Collecte et suivi satellite des champs.',
};

export const viewport: Viewport = { themeColor: '#163A2C', width: 'device-width', initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <body className="min-h-dvh">{children}</body>
    </html>
  );
}
