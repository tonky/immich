// Upstream's medium config (server/test/vitest.config.medium.mjs) with one change: its
// global setup starts `immich-app/postgres` through testcontainers (docker); this one
// migrates enve's postgres, which runs that image's server, extensions and settings
// (helpers/start-postgres.sh).
import { fileURLToPath } from 'node:url';
import upstream from '../vitest.config.medium.mjs';

export default {
  ...upstream,
  test: {
    ...upstream.test,
    globalSetup: [fileURLToPath(new URL('globalSetup.ts', import.meta.url))],
  },
};
