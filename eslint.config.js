// ESLint flat config (ESLint v9+) tuned for Dynamics 365 / Dataverse web resources.
// Form & ribbon scripts run in the browser and rely on the global `Xrm` object.

const js = require("@eslint/js");
const globals = require("globals");

module.exports = [
  js.configs.recommended,
  {
    files: ["WebResources/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "script", // classic web resources are non-module scripts
      globals: {
        ...globals.browser,
        // Dataverse client API globals
        Xrm: "readonly",
        GetGlobalContext: "readonly",
        executionContext: "readonly",
        formContext: "readonly"
      }
    },
    rules: {
      "no-unused-vars": ["warn", { argsIgnorePattern: "^_|^executionContext$" }],
      "no-undef": "error",
      "no-console": "warn",
      eqeqeq: ["error", "smart"],
      "prefer-const": "warn"
    }
  },
  {
    // Node/CommonJS tooling files (this config, build scripts, etc.)
    files: ["eslint.config.js", "*.config.js", "scripts/**/*.cjs"],
    languageOptions: {
      sourceType: "commonjs",
      globals: { ...globals.node }
    }
  },
  {
    // Apps under apps/ have their own lint setup; build output is never linted.
    ignores: ["node_modules/**", "apps/**", "azure/**", "**/dist/**", "**/bin/**", "**/obj/**", "**/*.min.js"]
  }
];
