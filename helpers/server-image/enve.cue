package enve

import "github.com/tonky/enve/schema/v1:schema"

// The e2e server's image stack, as upstream's server/Dockerfile runs it on
// ghcr.io/immich-app/base-server-prod:202610211607 (immich-app/base-images ffeb230c5a):
// node 24.21.0 (upstream's 24.22.1 is in no nixpkgs yet; an official build would load the
// nix-built sharp beside the host's glibc), libvips 8.18.7 with upstream's patch and
// options, and sharp 0.35.5 built
// against it (SHARP_FORCE_GLOBAL_LIBVIPS). The prebuilt @img/sharp-libvips cannot decode
// the test-assets' HEIC. ../server-image.sh hands it to start-immich-server.sh; an
// environment of its own keeps it out of the jobs that never start the server.
//
// Every input is pinned: the libraries by the lock (libheif 1.23.6 and libjxl 0.12.0 as
// upstream's), the sources as hashed fetches. Not upstream's own builds: libraw (0.22.2),
// ImageMagick (7.1.2-21), libde265 (1.0.16), libjpeg-turbo (jpegli).

profiles: dev: schema.#Profile & {
	name: "immich-server-image"
	tools: [
		{pname: "nodejs", version: "24.21.0"},
		// base-images server/sources/libvips.{json,sh}. Builds run in a temporary $out:
		// loaders are built in (no module dir) and the .pc files locate themselves.
		schema.#GenericBuildSpec & {
			pname:   "vips"
			version: "8.18.7"
			src:     "."
			fetch: {
				libvips: {url: "https://codeload.github.com/libvips/libvips/tar.gz/24ad4d042940e6bf99a68871ba886ca8847c9c82", sha256: "e5f4d145da2d7c06863281d1dfe9dd2d43ce89458d1584e1d16cb520ebfc9e86"}
				patch: {url: "https://raw.githubusercontent.com/immich-app/base-images/ffeb230c5ade36f0e603aecfaef62e943309640b/server/sources/libvips-patches/0001-put-other-loaders-ahead-of-dcrawload.patch", sha256: "a0eaf6d7d0b05a932f1c1cab2bc1c2d24d387239a26f94782289f1b9bcaedad3"}
			}
			buildInputs: [
				{pname: "meson"},
				{pname: "ninja"},
				{pname: "pkg-config", attr: "pkg-config.out"},
				{pname: "gcc", attr: "gcc.out"},
				{pname: "gnupatch"},
				{pname: "gnutar"},
				{pname: "gzip"},
				{pname: "gnused"},
				{pname: "coreutils"},
				// The libraries base-server-dev installs or builds, as libvips finds them.
				{pname: "glib", attr: "glib.dev"},
				{pname: "expat", attr: "expat.dev"},
				{pname: "zlib", attr: "zlib.dev"},
				{pname: "libexif"},
				{pname: "lcms2", attr: "lcms2.dev"},
				{pname: "libjpeg_turbo", attr: "libjpeg_turbo.dev"},
				{pname: "libpng", attr: "libpng.dev"},
				{pname: "libwebp"},
				{pname: "librsvg", attr: "librsvg.dev"},
				{pname: "gdk-pixbuf", attr: "gdk-pixbuf.dev"},
				{pname: "cairo", attr: "cairo.dev"},
				{pname: "libhwy"},
				{pname: "libheif", attr: "libheif.dev", version: "1.23.6"},
				{pname: "libjxl", attr: "libjxl.dev", version: "0.12.0"},
				{pname: "libraw", attr: "libraw.dev"},
				{pname: "imagemagick", attr: "imagemagick.dev"},
			]
			buildScript: """
				set -eu
				work=$(mktemp -d)
				tar -xzf "$libvips" -C "$work" --strip-components=1
				cd "$work"
				patch -p1 < "$patch"
				# The libraries' own lib dirs on the linker's search path. Only the .dev outputs
				# are inputs, so meson links their libraries by store path and adds a build
				# rpath to each lib dir, then strips those entries on install, the ld-wrapper's
				# identical ones with them: libvips shipped without glib's, expat's, … dirs
				# and the server's sharp failed to load (libexpat.so.1). Dirs the compiler
				# searches get no build rpath, so the wrapper's entries stay.
				for dir in $(pkg-config --libs-only-L glib-2.0 gio-2.0 gobject-2.0 expat zlib \\
				  MagickCore libexif libjpeg libpng libwebp libwebpmux libwebpdemux librsvg-2.0 \\
				  cairo lcms2 libraw_r libhwy libheif libjxl libjxl_threads); do
				  LIBRARY_PATH="${dir#-L}${LIBRARY_PATH:+:$LIBRARY_PATH}"
				done
				export LIBRARY_PATH
				# The programs in bin/ load the libvips beside them: meson installs them with
				# no RUNPATH into the output (nixpkgs' ld-wrapper adds one, enve's doesn't).
				if [ "$(uname -s)" = Linux ]; then export LDFLAGS='-Wl,-rpath,$ORIGIN/../lib'; fi
				meson setup build --buildtype=release --libdir=lib --prefix="$out" \\
				  -Dintrospection=disabled -Dtiff=disabled -Dmodules=disabled -Dauto_features=disabled \\
				  -Dexif=enabled -Dlcms=enabled -Djpeg=enabled -Dpng=enabled -Dwebp=enabled \\
				  -Drsvg=enabled -Dhighway=enabled -Dheif=enabled -Djpeg-xl=enabled -Draw=enabled \\
				  -Dmagick=enabled -Dzlib=enabled
				ninja -C build install
				sed -i 's|^prefix=.*|prefix=${pcfiledir}/../..|' "$out"/lib/pkgconfig/*.pc
				rm -rf "$work"
				# A library missing from the RUNPATH fails the build, not the server's dlopen.
				for lib in "$out"/lib/libvips.so.42 "$out"/lib/libvips-cpp.so.42; do
				  runpath=$(readelf -d "$lib" | sed -n 's/.*(RUNPATH).*\\[\\(.*\\)\\]/\\1/p')
				  for needed in $(readelf -d "$lib" | sed -n 's/.*(NEEDED).*\\[\\(.*\\)\\]/\\1/p'); do
				    case "$needed" in libvips.so.*) continue ;; esac
				    found=
				    IFS=:
				    for dir in $runpath; do [ -e "$dir/$needed" ] && found=1; done
				    unset IFS
				    [ -n "$found" ] || { echo "vips: $needed of ${lib##*/} is on no RUNPATH entry ($runpath)" >&2; exit 1; }
				  done
				done
				"$out/bin/vips" --version
				"""
		},
		// server/Dockerfile's sharp build. Its packages are the closure of sharp in upstream's
		// pnpm-lock.yaml, node-addon-api and node-gyp included (pnpm-workspace.yaml's
		// packageExtensions), at the lock's integrity (test: server_image_sharp_is_upstreams).
		schema.#GenericBuildSpec & {
			pname:   "sharp"
			version: "0.35.5"
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
				npm_node_addon_api:      {url: "https://registry.npmjs.org/node-addon-api/-/node-addon-api-8.9.2.tgz", hash: "sha512-VijLXbi3UACN69I0JVXJsX4tjACjNoQDgv2gTF6sx2wWEi8tkSg2eX8p5gSIFi8z2+DL3oHmY6OyKce38SDolg=="}
				npm_node_gyp:            {url: "https://registry.npmjs.org/node-gyp/-/node-gyp-13.1.0.tgz", hash: "sha512-FpNzOLFACKG0oRBYbZ5WOeWD1EqRTIWX90MaRIWTO18lVYPx8fqIjrdS3pihjnCkSmgop6zVGkSqg1vXZLksuw=="}
				npm_nopt:                {url: "https://registry.npmjs.org/nopt/-/nopt-10.0.1.tgz", hash: "sha512-df3sBr/6ax9hSGuC3CspvLlbnX8cP5L5nZwXF8cGN8l0zSWR6BvzmQ6jPUKjvo6+/xdpkNvEcucBNUdBeeV13g=="}
				npm_picomatch:           {url: "https://registry.npmjs.org/picomatch/-/picomatch-4.0.7.tgz", hash: "sha512-qcJu88Q2IWqJsDD529JKMdwGm/dvInW4HvQnRwiH9JtihJvzGOscDtHE3x1pBKeUOTysQ8kVmLnJ2kJu7yhcGA=="}
				npm_proc_log:            {url: "https://registry.npmjs.org/proc-log/-/proc-log-7.0.0.tgz", hash: "sha512-FYgfaA69XZ93zaXLoMNQ+ViDXGGBgR8aLh03txzcFhV+9xOXx7+8DLCULrKKpR9+GsH9ZfHm82aSUPpozX0Ztg=="}
				npm_semver:              {url: "https://registry.npmjs.org/semver/-/semver-7.8.5.tgz", hash: "sha512-Y7/KDsb8LjooZpwaqGyulO6DQlksgCncchHGk+sZIY4SBvUocMBEFH5Ur1fI4dV+Jvl0w6cjvucaIi40puRioA=="}
				npm_sharp:               {url: "https://registry.npmjs.org/sharp/-/sharp-0.35.5.tgz", hash: "sha512-Ywn4OnzGukp7CDMrp08RQ50YKmuwG47brZgIVPTvBaaAfQlRlygrRqSrxdCiL9M+LlzLBiJ68IR1QqvzHyjC7g=="}
				npm_tar:                 {url: "https://registry.npmjs.org/tar/-/tar-7.5.22.tgz", hash: "sha512-MFO/QzvtAOmJbkhOaCTvbGcFN9L9b+JunIsDwaKljSOdcLMea3NJ1k9Usz/rjdfSXTq4dfzfeS7W4p4YOAAHeA=="}
				npm_tinyglobby:          {url: "https://registry.npmjs.org/tinyglobby/-/tinyglobby-0.2.17.tgz", hash: "sha512-wXR/dYpcqKmfWpEdZjiKJOwCNFndD0DMnrW/cYjVGttEkBfVgcLFHoNrlj47mjOVic9yyNu65alsgF4NQyTa2g=="}
				npm_undici:              {url: "https://registry.npmjs.org/undici/-/undici-8.11.2.tgz", hash: "sha512-u4UB2/IrKdU6lFxumHmmo1a3fCQO5tzQllRorfoRS63txhrB7xTpSn1PftwC4qEHkOaqP95fCWW4lJzwErwzhQ=="}
				npm_which:               {url: "https://registry.npmjs.org/which/-/which-7.0.0.tgz", hash: "sha512-RancgH2dmbLdHl6LRhEqvklWMgl/Hdnun0Y90KhBOLkMefg8Qa7/Zel8Sm+8HEcP6DEjzsWzpkuBQEZok58isA=="}
				npm_yallist:             {url: "https://registry.npmjs.org/yallist/-/yallist-5.0.0.tgz", hash: "sha512-YgvUTfwqyc7UXVMrB+SImsVYSmTS8X/tSrtdNZMImM+n7+QTriRXyXim0mBrTXNeqzVF0KWGgHPeiyViFFrNDw=="}
			}
			buildInputs: [
				{pname: "vips"},
				{pname: "nodejs", version: "24.21.0"},
				{pname: "glib", attr: "glib.dev"},
				{pname: "pkg-config", attr: "pkg-config.out"},
				{pname: "gcc", attr: "gcc.out"},
				{pname: "gnumake"},
				{pname: "python3"},
				{pname: "gnutar"},
				{pname: "gzip"},
				{pname: "gnused"},
				{pname: "gnugrep"},
				{pname: "coreutils"},
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
				node_bin=$(command -v node)
				export npm_config_nodedir="${NODE_DIR:-$(dirname $(dirname "$node_bin"))}"
				SHARP_FORCE_GLOBAL_LIBVIPS=true npm run build
				"""
			exports: IMMICH_SHARP_PATH: "$out/node_modules/sharp"
		},
	]
}
