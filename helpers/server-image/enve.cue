package enve

import "github.com/tonky/enve/schema/v1:schema"

// The e2e server's image stack, as upstream's server/Dockerfile runs it on
// ghcr.io/immich-app/base-server-prod:202608251107 (immich-app/base-images ec26ee7152):
// node 24.18.0, libvips 8.18.5 with upstream's patch and options, and sharp 0.35.3 built
// against it (SHARP_FORCE_GLOBAL_LIBVIPS). The prebuilt @img/sharp-libvips cannot decode
// the test-assets' HEIC. ../server-image.sh hands it to start-immich-server.sh; an
// environment of its own keeps it out of the jobs that never start the server.
//
// Every input is pinned: the libraries at one nixpkgs revision (node 24.18.0's; libheif
// 1.23.1 and libjxl 0.12.0 as upstream's), the sources as hashed fetches. Not upstream's
// own builds: libraw 0.22.1 (0.22.2), ImageMagick 7.1.2-27 (-21), libde265 1.1.1
// (1.0.16), libjpeg-turbo (jpegli).
_rev: "6642eae1415ec8db2c4172690b1f7accc325e746"

profiles: dev: schema.#Profile & {
	name: "immich-server-image"
	tools: [
		{pname: "nodejs", version: "24.18.0", rev: _rev},
		// base-images server/sources/libvips.{json,sh}. Builds run in a temporary $out:
		// loaders are built in (no module dir) and the .pc files locate themselves.
		schema.#GenericBuildSpec & {
			pname:   "vips"
			version: "8.18.5"
			src:     "."
			fetch: {
				libvips: {url: "https://codeload.github.com/libvips/libvips/tar.gz/7c28da9c2b8b5b8defe54f2ae92ee474c0e2d6e4", sha256: "63a9806328f57eeb4ea7e7d596339e28ea9d1438609f7a79539814505d4d0a17"}
				patch: {url: "https://raw.githubusercontent.com/immich-app/base-images/ec26ee7152812f99209c5ad93126220eaa513eb9/server/sources/libvips-patches/0001-put-other-loaders-ahead-of-dcrawload.patch", sha256: "18346f89e043ebb2bfdfc2ca9c8df13f2e2318d4334ef57a9247ba57c1db2c60"}
			}
			buildInputs: [
				{pname: "meson", rev: _rev},
				{pname: "ninja", rev: _rev},
				{pname: "pkg-config", rev: _rev},
				{pname: "gcc", rev: _rev},
				{pname: "gnupatch", rev: _rev},
				// The libraries base-server-dev installs or builds, as libvips finds them.
				{pname: "glib", attr: "glib.dev", rev: _rev},
				{pname: "expat", attr: "expat.dev", rev: _rev},
				{pname: "zlib", attr: "zlib.dev", rev: _rev},
				{pname: "libexif", rev: _rev},
				{pname: "lcms2", attr: "lcms2.dev", rev: _rev},
				{pname: "libjpeg_turbo", attr: "libjpeg_turbo.dev", rev: _rev},
				{pname: "libpng", attr: "libpng.dev", rev: _rev},
				{pname: "libwebp", rev: _rev},
				{pname: "librsvg", attr: "librsvg.dev", rev: _rev},
				{pname: "libhwy", rev: _rev},
				{pname: "libheif", attr: "libheif.dev", rev: _rev},
				{pname: "libjxl", attr: "libjxl.dev", rev: _rev},
				{pname: "libraw", attr: "libraw.dev", rev: _rev},
				{pname: "imagemagick", attr: "imagemagick.dev", rev: _rev},
			]
			buildScript: """
				set -eu
				work=$(mktemp -d)
				tar -xzf "$libvips" -C "$work" --strip-components=1
				cd "$work"
				patch -p1 < "$patch"
				meson setup build --buildtype=release --libdir=lib --prefix="$out" \\
				  -Dintrospection=disabled -Dtiff=disabled -Dmodules=disabled -Dauto_features=disabled \\
				  -Dexif=enabled -Dlcms=enabled -Djpeg=enabled -Dpng=enabled -Dwebp=enabled \\
				  -Drsvg=enabled -Dhighway=enabled -Dheif=enabled -Djpeg-xl=enabled -Draw=enabled \\
				  -Dmagick=enabled -Dzlib=enabled
				ninja -C build install
				sed -i 's|^prefix=.*|prefix=${pcfiledir}/../..|' "$out"/lib/pkgconfig/*.pc
				rm -rf "$work"
				"""
		},
		// server/Dockerfile's sharp build. Its packages are the closure of sharp in upstream's
		// pnpm-lock.yaml, node-addon-api and node-gyp included (pnpm-workspace.yaml's
		// packageExtensions), at the lock's integrity (test: server_image_sharp_is_upstreams).
		schema.#GenericBuildSpec & {
			pname:   "sharp"
			version: "0.35.3"
			src:     "."
			fetch: {
				npm_img_colour:          {url: "https://registry.npmjs.org/@img/colour/-/colour-1.1.0.tgz", hash: "sha512-Td76q7j57o/tLVdgS746cYARfSyxk8iEfRxewL9h4OMzYhbW4TAcppl0mT4eyqXddh6L/jwoM75mo7ixa/pCeQ=="}
				npm_isaacs_fs_minipass:  {url: "https://registry.npmjs.org/@isaacs/fs-minipass/-/fs-minipass-4.0.1.tgz", hash: "sha512-wgm9Ehl2jpeqP3zw/7mo3kRHFp5MEDhqAdwy1fTGkHAwnkGOVsgpvQhL8B5n1qlb01jV3n/bI0ZfZp5lWA1k4w=="}
				npm_abbrev:              {url: "https://registry.npmjs.org/abbrev/-/abbrev-5.0.0.tgz", hash: "sha512-/XrFJgzQQQHpti1raDJC6m4ws6aNktmjBlhk8Fdlk7LwCEuDoieEJJY9OFHjfiFJFFRM2tK+Ky/IsfbbmlMu1w=="}
				npm_chownr:              {url: "https://registry.npmjs.org/chownr/-/chownr-3.0.0.tgz", hash: "sha512-+IxzY9BZOQd/XuYPRmrvEVjF/nqj5kgT4kEq7VofrDoM1MxoRjEWkrCC3EtLi59TVawxTAn+orJwFQcrqEN1+g=="}
				npm_detect_libc:         {url: "https://registry.npmjs.org/detect-libc/-/detect-libc-2.1.2.tgz", hash: "sha512-Btj2BOOO83o3WyH59e8MgXsxEQVcarkUOpEYrubB0urwnN10yQ364rsiByU11nZlqWYZm05i/of7io4mzihBtQ=="}
				npm_env_paths:           {url: "https://registry.npmjs.org/env-paths/-/env-paths-2.2.1.tgz", hash: "sha512-+h1lkLKhZMTYjog1VEpJNG7NZJWcuc2DDk/qsqSTRRCOXiLjeQ1d1/udrUGhqMxUgAlwKNZ0cf2uqan5GLuS2A=="}
				npm_exponential_backoff: {url: "https://registry.npmjs.org/exponential-backoff/-/exponential-backoff-3.1.3.tgz", hash: "sha512-ZgEeZXj30q+I0EN+CbSSpIyPaJ5HVQD18Z1m+u1FXbAeT94mr1zw50q4q6jiiC447Nl/YTcIYSAftiGqetwXCA=="}
				npm_fdir:                {url: "https://registry.npmjs.org/fdir/-/fdir-6.5.0.tgz", hash: "sha512-tIbYtZbucOs0BRGqPJkshJUYdL+SDH7dVM8gjy+ERp3WAUjLEFJE+02kanyHtwjWOnwrKYBiwAmM0p4kLJAnXg=="}
				npm_graceful_fs:         {url: "https://registry.npmjs.org/graceful-fs/-/graceful-fs-4.2.11.tgz", hash: "sha512-RbJ5/jmFcNNCcDV5o9eTnBLJ/HszWV0P73bc+Ff4nS/rJj+YaS6IGyiOL0VoBYX+l1Wrl3k63h/KrH+nhJ0XvQ=="}
				npm_isexe:               {url: "https://registry.npmjs.org/isexe/-/isexe-4.0.0.tgz", hash: "sha512-FFUtZMpoZ8RqHS3XeXEmHWLA4thH+ZxCv2lOiPIn1Xc7CxrqhWzNSDzD+/chS/zbYezmiwWLdQC09JdQKmthOw=="}
				npm_minipass:            {url: "https://registry.npmjs.org/minipass/-/minipass-7.1.3.tgz", hash: "sha512-tEBHqDnIoM/1rXME1zgka9g6Q2lcoCkxHLuc7ODJ5BxbP5d4c2Z5cGgtXAku59200Cx7diuHTOYfSBD8n6mm8A=="}
				npm_minizlib:            {url: "https://registry.npmjs.org/minizlib/-/minizlib-3.1.0.tgz", hash: "sha512-KZxYo1BUkWD2TVFLr0MQoM8vUUigWD3LlD83a/75BqC+4qE0Hb1Vo5v1FgcfaNXvfXzr+5EhQ6ing/CaBijTlw=="}
				npm_node_addon_api:      {url: "https://registry.npmjs.org/node-addon-api/-/node-addon-api-8.8.0.tgz", hash: "sha512-c5Ko1fZJIJmzhFIkhRN76WTq+fC6tWnGy9CXA0fA+XygsWZmEwG8vmbkNqxMyoaa0Tin4djul49NzdVcJJcjeA=="}
				npm_node_gyp:            {url: "https://registry.npmjs.org/node-gyp/-/node-gyp-13.0.0.tgz", hash: "sha512-FYYyBDWdc+kzoyPd5PqHUgM9DGs1C/Z4jxBZAOnA2GRUVXPivKRREq5q+VVPXVr9aGVqGMaMqyFHbviy/yb7Hg=="}
				npm_nopt:                {url: "https://registry.npmjs.org/nopt/-/nopt-10.0.1.tgz", hash: "sha512-df3sBr/6ax9hSGuC3CspvLlbnX8cP5L5nZwXF8cGN8l0zSWR6BvzmQ6jPUKjvo6+/xdpkNvEcucBNUdBeeV13g=="}
				npm_picomatch:           {url: "https://registry.npmjs.org/picomatch/-/picomatch-4.0.7.tgz", hash: "sha512-qcJu88Q2IWqJsDD529JKMdwGm/dvInW4HvQnRwiH9JtihJvzGOscDtHE3x1pBKeUOTysQ8kVmLnJ2kJu7yhcGA=="}
				npm_proc_log:            {url: "https://registry.npmjs.org/proc-log/-/proc-log-7.0.0.tgz", hash: "sha512-FYgfaA69XZ93zaXLoMNQ+ViDXGGBgR8aLh03txzcFhV+9xOXx7+8DLCULrKKpR9+GsH9ZfHm82aSUPpozX0Ztg=="}
				npm_semver:              {url: "https://registry.npmjs.org/semver/-/semver-7.8.5.tgz", hash: "sha512-Y7/KDsb8LjooZpwaqGyulO6DQlksgCncchHGk+sZIY4SBvUocMBEFH5Ur1fI4dV+Jvl0w6cjvucaIi40puRioA=="}
				npm_sharp:               {url: "https://registry.npmjs.org/sharp/-/sharp-0.35.3.tgz", hash: "sha512-ej0zVHuZGHCiABXcNxeYhpRnPNPAcvbG8RMdBAhDAxLKkCRVSpK3Iyu7qbqw3JMzoj0REeM6f3tJLtVwl0023Q=="}
				npm_tar:                 {url: "https://registry.npmjs.org/tar/-/tar-7.5.16.tgz", hash: "sha512-56adEpPMouktRlBLXiaYFFzZ/3+JXa8P9n7WbR+ibIjtviN55mEaOkiysCnPnWm+7kkui1Dn8J9l+g6zV8731w=="}
				npm_tinyglobby:          {url: "https://registry.npmjs.org/tinyglobby/-/tinyglobby-0.2.17.tgz", hash: "sha512-wXR/dYpcqKmfWpEdZjiKJOwCNFndD0DMnrW/cYjVGttEkBfVgcLFHoNrlj47mjOVic9yyNu65alsgF4NQyTa2g=="}
				npm_undici:              {url: "https://registry.npmjs.org/undici/-/undici-6.26.0.tgz", hash: "sha512-4yqz8a3n5HmGTlsbADNtr/dJlhkh/55Rq798G6ibiULcXbDtaLpTl1pvdqcbFfeoj3iSi52lePFM7h9H21cw/A=="}
				npm_which:               {url: "https://registry.npmjs.org/which/-/which-7.0.0.tgz", hash: "sha512-RancgH2dmbLdHl6LRhEqvklWMgl/Hdnun0Y90KhBOLkMefg8Qa7/Zel8Sm+8HEcP6DEjzsWzpkuBQEZok58isA=="}
				npm_yallist:             {url: "https://registry.npmjs.org/yallist/-/yallist-5.0.0.tgz", hash: "sha512-YgvUTfwqyc7UXVMrB+SImsVYSmTS8X/tSrtdNZMImM+n7+QTriRXyXim0mBrTXNeqzVF0KWGgHPeiyViFFrNDw=="}
			}
			buildInputs: [
				{pname: "vips"},
				{pname: "nodejs", version: "24.18.0", rev: _rev},
				{pname: "glib", attr: "glib.dev", rev: _rev},
				{pname: "pkg-config", rev: _rev},
				{pname: "gcc", rev: _rev},
				{pname: "gnumake", rev: _rev},
				{pname: "python3", rev: _rev},
			]
			buildScript: """
				set -eu
				unpack() { mkdir -p "$out/node_modules/$2"; tar -xzf "$1" -C "$out/node_modules/$2" --strip-components=1; }
				unpack "$npm_img_colour" @img/colour
				unpack "$npm_isaacs_fs_minipass" @isaacs/fs-minipass
				unpack "$npm_abbrev" abbrev
				unpack "$npm_chownr" chownr
				unpack "$npm_detect_libc" detect-libc
				unpack "$npm_env_paths" env-paths
				unpack "$npm_exponential_backoff" exponential-backoff
				unpack "$npm_fdir" fdir
				unpack "$npm_graceful_fs" graceful-fs
				unpack "$npm_isexe" isexe
				unpack "$npm_minipass" minipass
				unpack "$npm_minizlib" minizlib
				unpack "$npm_node_addon_api" node-addon-api
				unpack "$npm_node_gyp" node-gyp
				unpack "$npm_nopt" nopt
				unpack "$npm_picomatch" picomatch
				unpack "$npm_proc_log" proc-log
				unpack "$npm_semver" semver
				unpack "$npm_sharp" sharp
				unpack "$npm_tar" tar
				unpack "$npm_tinyglobby" tinyglobby
				unpack "$npm_undici" undici
				unpack "$npm_which" which
				unpack "$npm_yallist" yallist
				cd "$out/node_modules/sharp"
				# The headers of the node it runs on, not a download (node-gyp's default).
				export npm_config_nodedir="$NODE_DIR"
				SHARP_FORCE_GLOBAL_LIBVIPS=true npm run build
				"""
			exports: IMMICH_SHARP_PATH: "$out/node_modules/sharp"
		},
	]
}
