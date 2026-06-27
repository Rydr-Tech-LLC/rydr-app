import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "#111111",
        charcoal: "#151515",
        ivory: "#f5efe2",
        champagne: "#d8bd82",
        rydr: {
          red: "#ff0000",
          burgundy: "#800021"
        },
        muted: "#626977",
        line: "rgba(17, 17, 17, 0.08)",
        surface: "#ffffff",
        grouped: "#f7f7fa"
      },
      borderRadius: {
        lg: "16px",
        md: "12px",
        sm: "8px"
      },
      boxShadow: {
        sm: "0 1px 2px rgba(17,17,17,0.06)",
        md: "0 8px 24px rgba(17,17,17,0.08)",
        lg: "0 24px 48px rgba(17,17,17,0.14)"
      },
      fontFamily: {
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          "SF Pro Display",
          "SF Pro Text",
          "Segoe UI",
          "sans-serif"
        ]
      }
    }
  },
  plugins: []
};

export default config;
