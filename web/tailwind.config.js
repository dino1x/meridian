/** @type {import('tailwindcss').Config} */
// Meridian design system: one dark palette, one sans + one mono, shared across the shell and all eight modules.
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['"Inter Tight"', 'Inter', 'system-ui', 'sans-serif'],
        mono: ['"Geist Mono"', 'ui-monospace', 'SFMono-Regular', 'monospace'],
      },
      colors: {
        base: '#0A0B0D', // page
        surface: '#111317', // panels
        raised: '#171A1F', // inputs, nested cells
        line: 'rgba(255,255,255,0.08)', // hairlines
        fg: '#ECEEF1', // primary text
        muted: '#8A9099', // secondary text
        faint: '#5C626B', // labels, axes
        copper: '#E59A38', // brand + primary action
        ice: '#9FC2FF', // live data, charts
        pos: '#3DD68C',
        neg: '#F2555A',
        warn: '#F5B84A',
        paper: '#F4F1EA', // receipts and certificates (the only light surface)
        ink: '#16171B', // text on paper
      },
      borderRadius: {
        panel: '14px',
      },
    },
  },
  plugins: [],
};
