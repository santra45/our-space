/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        blush: {
          50: '#fff5f7',
          100: '#ffe8ed',
          200: '#ffd1dc',
          300: '#ffb3c5',
          400: '#ff85a3',
          500: '#ff5480',
          600: '#f02861',
        },
        cream: {
          50: '#fdfcf7',
          100: '#fcf8ee',
          200: '#f9f1dc',
          300: '#f4e5bf',
        },
        lavender: {
          50: '#f8f7ff',
          100: '#f0edff',
          200: '#e2dcff',
          300: '#cdbeff',
          400: '#b196ff',
        },
        matcha: {
          50: '#f4f8f3',
          100: '#e5f0e3',
          200: '#cbdec8',
          300: '#a7c6a2',
        },
        caramel: {
          100: '#f3e8dc',
          200: '#e7d1b8',
          400: '#c59b6d',
        }
      },
      borderRadius: {
        '3xl': '1.5rem',
        '4xl': '2rem',
        '5xl': '2.5rem',
      },
      fontFamily: {
        sans: ['"Plus Jakarta Sans"', 'Nunito', 'sans-serif'],
        handwriting: ['"Caveat"', '"Indie Flower"', 'cursive'],
      },
      boxShadow: {
        'cozy': '0 8px 30px rgba(255, 182, 193, 0.25)',
        'polaroid': '0 10px 25px -5px rgba(0, 0, 0, 0.1), 0 8px 10px -6px rgba(0, 0, 0, 0.08)',
        'glass': '0 8px 32px 0 rgba(255, 182, 193, 0.2)',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0px) rotate(0deg)' },
          '50%': { transform: 'translateY(-8px) rotate(2deg)' },
        },
        wobble: {
          '0%, 100%': { transform: 'rotate(-2deg)' },
          '50%': { transform: 'rotate(2deg)' },
        },
        shimmer: {
          '100%': { transform: 'translateX(100%)' },
        }
      },
      animation: {
        'float-slow': 'float 4s ease-in-out infinite',
        'float-medium': 'float 3s ease-in-out infinite',
        'wobble-soft': 'wobble 2s ease-in-out infinite',
      }
    },
  },
  plugins: [],
}
