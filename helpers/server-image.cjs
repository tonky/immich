// ==============================================================================
// server-image.cjs - Resolves `sharp` to the one in $IMMICH_SHARP_PATH
// ==============================================================================
// Preloaded by start-immich-server.sh (`NODE_OPTIONS=--require`): the server's sharp is
// then the image's (helpers/server-image.sh), whose libvips decodes the HEIC, JXL and RAW
// test-assets the prebuilt @img/sharp-libvips cannot. The same sharp as the server's
// lockfile; every other module resolves as before.
'use strict';

const { registerHooks } = require('node:module');
const { pathToFileURL } = require('node:url');

const dir = process.env.IMMICH_SHARP_PATH;
if (!dir) {
  throw new Error('server-image.cjs: IMMICH_SHARP_PATH is unset (helpers/server-image.sh prints it)');
}
const url = pathToFileURL(require.resolve(dir)).href;

registerHooks({
  resolve: (specifier, context, nextResolve) =>
    specifier === 'sharp' ? { url, format: 'commonjs', shortCircuit: true } : nextResolve(specifier, context),
});
