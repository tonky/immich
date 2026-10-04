package enve

import (
	"github.com/tonky/enve/pkgs:pkgs"
	"github.com/tonky/enve/schema/v1:schema"
)

// libvips with HEIC, JXL and RAW for the e2e server, until sharp builds from source here:
// the prebuilt @img/sharp-libvips cannot decode the test-assets' HEIC. Only nixpkgs'
// immich's sharp is used (`lib/node_modules/immich/node_modules/sharp`, built against
// nixpkgs' vips with SHARP_FORCE_GLOBAL_LIBVIPS): ../store-sharp.sh. An environment of its
// own keeps the 1.5 GiB closure out of the jobs that never start the server, and its
// binaries (immich-admin, server) off the server's PATH.
profiles: dev: schema.#Profile & {
	name: "immich-store-sharp"
	tools: [{pname: "immich"}, pkgs.nodejs & {version: "24"}]
}
