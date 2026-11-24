// Repris de Fieldproof (apps/web/next.config.ts) : sans Netlify ni lien sécurisé.
/** @type {import('next').NextConfig} */
const nextConfig = {
  images: { unoptimized: true },
  // En développement, l'indicateur de Next ne doit pas cacher le menu du compte, en bas du rail.
  devIndicators: { position: 'bottom-right' },
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'Referrer-Policy', value: 'same-origin' },
        ],
      },
    ];
  },
};

export default nextConfig;
