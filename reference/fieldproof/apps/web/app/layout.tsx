import type { Metadata, Viewport } from 'next';
import { Fraunces, Geist } from 'next/font/google';
import { Toaster } from 'sonner';
import './globals.css';

const display = Fraunces({ subsets: ['latin', 'latin-ext'], variable: '--font-display', axes: ['opsz', 'SOFT'] });
const sans = Geist({ subsets: ['latin', 'latin-ext'], variable: '--font-sans' });

export const metadata: Metadata = {
  title: { default: 'Fieldproof', template: '%s · Fieldproof' },
  description: 'Collecte terrain, envoi des dossiers clients au prêteur et preuve satellite de l’exploitation.',
  icons: { icon: '/icon.svg' },
};

export const viewport: Viewport = { themeColor: '#163A2C', width: 'device-width', initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr" className={`${display.variable} ${sans.variable}`}>
      <body className="min-h-dvh">
        {children}
        <Toaster
          position="top-center"
          richColors
          closeButton
          toastOptions={{ style: { fontFamily: 'var(--font-sans)' }, duration: 6000 }}
        />
      </body>
    </html>
  );
}
