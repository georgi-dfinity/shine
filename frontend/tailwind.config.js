/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "index.html",
    "src/**/*.{js,ts,jsx,tsx,html,css}",
  ],
  theme: {
    extend: {
      fontFamily: {
        inter: ["Inter", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"],
        poppins: ["Poppins", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"],
      },
    },
  },
  plugins: [require("@tailwindcss/typography")],
};


