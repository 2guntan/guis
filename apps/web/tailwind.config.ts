import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}', './lib/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        paper: '#F4F1E8',
        surface: '#FFFDF7',
        linen: '#F1EFE8',
        sand: { 50: '#F7F4EA', 100: '#EEE8D9', 200: '#E3DBC7', 300: '#CFC4AA' },
        ink: { DEFAULT: '#1A2620', soft: '#4A564F', faint: '#7C857E' },
        forest: { 50: '#E8F0EA', 100: '#CFE0D4', 300: '#7FA68C', 500: '#2F6B4F', 700: '#1E4D3A', 800: '#163A2C', 900: '#0F2A1F' },
        ochre: { 50: '#FBF2DF', 100: '#F4E0B5', 400: '#D9A23F', 500: '#C08A2B', 700: '#8A5F14' },
        clay: { 50: '#FBEAE6', 500: '#B5482F', 700: '#8C3320' },
        sky: { 50: '#E9F0F5', 100: '#D9E6EF', 500: '#3E6E8E', 700: '#2A5069' },
      },
      fontFamily: {
        display: ['var(--font-display)', 'Georgia', 'serif'],
        sans: ['var(--font-sans)', 'system-ui', 'sans-serif'],
      },
      boxShadow: {
        card: '0 1px 0 rgba(26,38,32,0.04), 0 8px 24px -16px rgba(22,58,44,0.25)',
        lift: '0 18px 40px -24px rgba(15,42,31,0.45)',
      },
      keyframes: {
        'fade-in': { from: { opacity: '0' }, to: { opacity: '1' } },
        'rise': { from: { opacity: '0', transform: 'translateY(8px)' }, to: { opacity: '1', transform: 'none' } },
        'draw': { from: { strokeDashoffset: '120' }, to: { strokeDashoffset: '0' } },
      },
      animation: {
        'fade-in': 'fade-in 160ms ease-out',
        rise: 'rise 220ms ease-out',
        draw: 'draw 1.4s ease-out forwards',
      },
    },
  },
  plugins: [],
};
export default config;
