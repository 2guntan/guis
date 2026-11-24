import type { Config } from 'tailwindcss';

// Jetons de docs/design/SPECS.md (maquettes V1). Communs, puis direction B « Relevé » du tableau de bord.
const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}', './lib/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Communs
        sand: { DEFAULT: '#F4EEE1', deep: '#E9DFCB' },
        surface: '#FFFFFF',
        ink: { DEFAULT: '#1E2420', muted: '#5A635D' },
        forest: { DEFAULT: '#1F4D3A', dark: '#163A2C', rail: '#2E6A51', soft: '#BFD3C7' },
        ochre: { DEFAULT: '#C8892B', soft: '#F5E9D3', text: '#8A5F14' },
        clay: { DEFAULT: '#B4442F', soft: '#F3DED8', text: '#8C3320' },
        sky: { DEFAULT: '#2F6B8E', soft: '#DCE7EE', text: '#24526D' },
        // Direction B
        chalk: '#EEF1EC',
        line: { DEFAULT: '#D3DAD0', soft: '#E5EAE2' },
        board: { text: '#163A2C', muted: '#4F5F55', help: '#6B7A70' },
        alert: { DEFAULT: '#E0A100', bg: '#FFF6DC', text: '#6E4E00' },
        // Rampe NDVI (carte et légende web)
        ndvi: { wait: '#D5D8D0', bare: '#B49A74', emerge: '#A9C47F', grow: '#5E9B4E', peak: '#1F5E33', senesce: '#C9A24A' },
      },
      fontFamily: {
        display: ['var(--font-display)', 'Georgia', 'serif'],
        sans: ['var(--font-body)', 'system-ui', 'sans-serif'],
      },
      borderRadius: { sm: '6px', md: '8px', lg: '12px', xl: '20px' },
    },
  },
  plugins: [],
};
export default config;
