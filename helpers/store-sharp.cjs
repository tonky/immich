// ==============================================================================
// store-sharp.cjs - Resolves `sharp` to the one in $IMMICH_SHARP_PATH
// ==============================================================================
// Preloaded by start-immich-server.sh (`NODE_OPTIONS=--require`): the server's sharp is
// then nixpkgs' (helpers/store-sharp.sh), whose libvips decodes the HEIC, JXL and RAW
// test-assets the prebuilt @img/sharp-libvips cannot. The same sharp minor as the
// server's (0.35); every other module resolves as before.
'use strict';

const { registerHooks } = require('node:module');
const { pathToFileURL } = require('node:url');

const dir = process.env.IMMICH_SHARP_PATH;
if (!dir) {
  throw new Error('store-sharp.cjs: IMMICH_SHARP_PATH is unset (helpers/store-sharp.sh prints it)');
}
const url = pathToFileURL(require.resolve(dir)).href;

registerHooks({
  resolve: (specifier, context, nextResolve) =>
    specifier === 'sharp' ? { url, format: 'commonjs', shortCircuit: true } : nextResolve(specifier, context),
});
