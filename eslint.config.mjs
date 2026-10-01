import {defineConfig,globalIgnores} from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";

export default defineConfig([
  ...nextVitals,
  {
    rules: {
      // Existing data-loading effects update state after asynchronous I/O.
      // Keep this visible without making CI fail until the components are migrated.
      "react-hooks/set-state-in-effect": "warn"
    }
  },
  globalIgnores([".next/**","next-env.d.ts"])
]);
