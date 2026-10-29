package enve

import (
	"list"
	"github.com/tonky/enve/schema/v1:schema"
	"github.com/tonky/enve/pkgs:pkgs"
	"immich.app/helpers/vchord"
)

// Upstream's pins that nixpkgs never shipped, as their release archives; where upstream
// publishes none for darwin (the postgres extensions), built from source there.
// tests/conformance.rs checks the versions against upstream's.

// The medium specs assert ffprobe's packet counts and timings: jellyfin's build, as
// upstream's server image ships it.
let ffmpeg = schema.#ArchiveBuildSpec & {
	pname:   "jellyfin-ffmpeg"
	version: "7.1.3-6"
	src: {
		"x86_64-linux":   "https://github.com/jellyfin/jellyfin-ffmpeg/releases/download/v7.1.3-6/jellyfin-ffmpeg_7.1.3-6_portable_linux64-gpl.tar.xz"
		"aarch64-linux":  "https://github.com/jellyfin/jellyfin-ffmpeg/releases/download/v7.1.3-6/jellyfin-ffmpeg_7.1.3-6_portable_linuxarm64-gpl.tar.xz"
		"x86_64-darwin":  "https://github.com/jellyfin/jellyfin-ffmpeg/releases/download/v7.1.3-6/jellyfin-ffmpeg_7.1.3-6_portable_mac64-gpl.tar.xz"
		"aarch64-darwin": "https://github.com/jellyfin/jellyfin-ffmpeg/releases/download/v7.1.3-6/jellyfin-ffmpeg_7.1.3-6_portable_macarm64-gpl.tar.xz"
	}
	sha256: {
		"x86_64-linux":   "39e99a7927468a6abec5f65d00f55010e8ff2ae3c2605294f179c94f6ae21af2"
		"aarch64-linux":  "bea03c670e8cc5bfe9edc0c5d624d4735421610cef5e808db93e7d8596952886"
		"x86_64-darwin":  "066ede9774aaae97a18098aaeea8b7e0d286653eb8618f640476e99c59a536c2"
		"aarch64-darwin": "e024d5e78d5414e75f0181036cd21373fafb9270c72894dfd7dbda2572439820"
	}
	installPhase: "mkdir -p \"$out/bin\" && cp ffmpeg ffprobe \"$out/bin/\""
}

// .nvmrc's node (upstream's base images run it too): nixpkgs has no 24.22.1 yet.
let nodejs = schema.#ArchiveBuildSpec & {
	pname:   "nodejs"
	version: "24.22.1"
	src: {
		"x86_64-linux":   "https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-x64.tar.xz"
		"aarch64-linux":  "https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-arm64.tar.xz"
		"x86_64-darwin":  "https://nodejs.org/dist/v24.22.1/node-v24.22.1-darwin-x64.tar.xz"
		"aarch64-darwin": "https://nodejs.org/dist/v24.22.1/node-v24.22.1-darwin-arm64.tar.xz"
	}
	sha256: {
		"x86_64-linux":   "6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6"
		"aarch64-linux":  "dbabf7a1cbf947e6059ffad2c27b80041db97dea1e553b62afdee7f13fca336e"
		"x86_64-darwin":  "65e450f90a6eaacd5000f611861c4ce65fadc87f813795dc4ed0c0e5f2fca2d4"
		"aarch64-darwin": "654ba79de6155647e22321932b45f2a1ccb705976cc337c9b8e278beb085a628"
	}
	installPhase: "mkdir -p \"$out\" && cp -R bin include lib share \"$out/\""
}

// package.json's `packageManager` pnpm, exactly (nixpkgs has 12.9): its native build
// (@pnpm/exe.*), which npm's `pnpm` package downloads on first run. At another version
// pnpm switches itself to that one, and doing so wrote the switch into pnpm-lock.yaml
// (`packageManagerDependencies`: `@pnpm/exe`): any `pnpm` run edited a tracked file, and
// the traced services digested it (pnpm 11 dropped `manage-package-manager-versions`).
let pnpm = schema.#ArchiveBuildSpec & {
	pname:   "pnpm"
	version: "12.14.0"
	src: {
		"x86_64-linux":   "https://registry.npmjs.org/@pnpm/exe.linux-x64/-/exe.linux-x64-12.14.0.tgz"
		"aarch64-linux":  "https://registry.npmjs.org/@pnpm/exe.linux-arm64/-/exe.linux-arm64-12.14.0.tgz"
		"x86_64-darwin":  "https://registry.npmjs.org/@pnpm/exe.darwin-x64/-/exe.darwin-x64-12.14.0.tgz"
		"aarch64-darwin": "https://registry.npmjs.org/@pnpm/exe.darwin-arm64/-/exe.darwin-arm64-12.14.0.tgz"
	}
	sha256: {
		"x86_64-linux":   "1de98ed2e9621113b0887b06322b461efb9df73d913fc1d151039b10b7117a41"
		"aarch64-linux":  "e7ca24224eb626a032828ec584c67903ad2f389911b849d009ed70a19f70d8d3"
		"x86_64-darwin":  "4fe5aa6c0ba3013f8aefb1cc23dd3c54f7272814be4b0275eb4d6a98d7769e26"
		"aarch64-darwin": "06136920c9cccad4f615bb080e054d9ac086fedfc32497bd87a892b7a4586f6f"
	}
	installPhase: "mkdir -p \"$out/bin\" && cp pnpm \"$out/bin/\" && chmod +x \"$out/bin/pnpm\""
}

// machine-learning/mise.toml's uv.
let uv = schema.#ArchiveBuildSpec & {
	pname:   "uv"
	version: "0.8.15"
	src: {
		"x86_64-linux":   "https://github.com/astral-sh/uv/releases/download/0.8.15/uv-x86_64-unknown-linux-gnu.tar.gz"
		"aarch64-linux":  "https://github.com/astral-sh/uv/releases/download/0.8.15/uv-aarch64-unknown-linux-gnu.tar.gz"
		"x86_64-darwin":  "https://github.com/astral-sh/uv/releases/download/0.8.15/uv-x86_64-apple-darwin.tar.gz"
		"aarch64-darwin": "https://github.com/astral-sh/uv/releases/download/0.8.15/uv-aarch64-apple-darwin.tar.gz"
	}
	sha256: {
		"x86_64-linux":   "be9878e9d08ebcb621a683aba52e7fb8bbf92b2532e0d759026ffcc067673042"
		"aarch64-linux":  "6ede0fefa7db7be3d5d9eda8784a8e43b1cf5410720eb3da60ab1d2f66678e82"
		"x86_64-darwin":  "2bbef70982e97dfc36454de173f35ec1a5e83ae11e3885df6a50db3fd76171cb"
		"aarch64-darwin": "103367962c5cb00bf7370d84cbaa3fec5a9807be9cc833ea9d8eea400c119fa2"
	}
	installPhase: "mkdir -p \"$out/bin\" && cp uv uvx \"$out/bin/\""
}

// The core plugin's build (mise.toml): extism-js compiles it, running binaryen's
// wasm-merge and wasm-opt.
let extismJs = schema.#ArchiveBuildSpec & {
	pname:   "extism-js"
	version: "1.7.0"
	src: {
		"x86_64-linux":   "https://github.com/extism/js-pdk/releases/download/v1.7.0/extism-js-x86_64-linux-v1.7.0.gz"
		"aarch64-linux":  "https://github.com/extism/js-pdk/releases/download/v1.7.0/extism-js-aarch64-linux-v1.7.0.gz"
		"x86_64-darwin":  "https://github.com/extism/js-pdk/releases/download/v1.7.0/extism-js-x86_64-macos-v1.7.0.gz"
		"aarch64-darwin": "https://github.com/extism/js-pdk/releases/download/v1.7.0/extism-js-aarch64-macos-v1.7.0.gz"
	}
	sha256: {
		"x86_64-linux":   "63b72da2f5e88655522dc21477de549f238a2f40546a69ce4e0fce7e78654035"
		"aarch64-linux":  "025f4050b199d68413c159bde1187271ae270021a9f7171e7beb509922821f2a"
		"x86_64-darwin":  "cce4a756eceb34b5aaac5ea864607d6c8b0610535e2c1b0c05a96bdbda69c7bb"
		"aarch64-darwin": "12c01c2bb2240a6a05a4f8babe680c793c397d84e6a1497a7ca1312e78a475c3"
	}
	installPhase: "mkdir -p \"$out/bin\" && cp extism-js \"$out/bin/\""
}

// Upstream's `version_124`; its darwin binaries load lib/libbinaryen.dylib beside them.
let binaryen = schema.#ArchiveBuildSpec & {
	pname:   "binaryen"
	version: "124"
	src: {
		"x86_64-linux":   "https://github.com/WebAssembly/binaryen/releases/download/version_124/binaryen-version_124-x86_64-linux.tar.gz"
		"aarch64-linux":  "https://github.com/WebAssembly/binaryen/releases/download/version_124/binaryen-version_124-aarch64-linux.tar.gz"
		"x86_64-darwin":  "https://github.com/WebAssembly/binaryen/releases/download/version_124/binaryen-version_124-x86_64-macos.tar.gz"
		"aarch64-darwin": "https://github.com/WebAssembly/binaryen/releases/download/version_124/binaryen-version_124-arm64-macos.tar.gz"
	}
	sha256: {
		"x86_64-linux":   "0290c3779fedf592b8da0ded3032ff55c41a2b7bfa2d6bf7b7bac6f0e6e28963"
		"aarch64-linux":  "6291bd9a57d8e046f3bc099a4db386c147433a87f71c783a901c5b1792e38de3"
		"x86_64-darwin":  "b389bb0731758d86c3cb266d01d28a12725c23bd3cabc3df34faa162af0887e9"
		"aarch64-darwin": "86a2c960ff62c6d2ea6009d1f89745c22c70100d394a095eab45eb941bdaa24c"
	}
	installPhase: "mkdir -p \"$out\" && cp -R bin lib \"$out/\""
}

// The extensions of upstream's test image (`ghcr.io/immich-app/postgres:14-vectorchord0.4.3`,
// PostgreSQL 14 from PGDG on Debian), laid out as nixpkgs' are (`lib/<module>`,
// `share/postgresql/extension/`) for the postgres service to join. On Linux the image's
// own builds: pgvector's PGDG package and VectorChord's release.
let pgvector = schema.#ArchiveBuildSpec & {
	pname:   "pgvector"
	version: "0.8.1"
	platforms: [schema.#Platform.Linux]
	src: {
		"x86_64-linux":  "https://apt-archive.postgresql.org/pub/repos/apt/pool/main/p/pgvector/postgresql-14-pgvector_0.8.1-1.pgdg12%2B1_amd64.deb"
		"aarch64-linux": "https://apt-archive.postgresql.org/pub/repos/apt/pool/main/p/pgvector/postgresql-14-pgvector_0.8.1-1.pgdg12%2B1_arm64.deb"
	}
	sha256: {
		"x86_64-linux":  "918c3ba72f83d778aa6cc01f1f4235271ea18abd397395d59f35d47f21770d6d"
		"aarch64-linux": "61505921f94a75aa6ef5042770c46856c962135479babfa6e36dad7bb7f48668"
	}
	// The package's usr/ tree.
	installPhase: """
		mkdir -p "$out/lib" "$out/share/postgresql"
		cp lib/postgresql/14/lib/vector.so "$out/lib/"
		cp -R share/postgresql/14/extension "$out/share/postgresql/"
		"""
}

let vchordLinux = schema.#ArchiveBuildSpec & {
	pname:   "vchord"
	version: vchord.version
	platforms: [schema.#Platform.Linux]
	src: {
		"x86_64-linux":  "https://github.com/tensorchord/VectorChord/releases/download/\(version)/postgresql-14-vchord_\(version)_x86_64-linux-gnu.zip"
		"aarch64-linux": "https://github.com/tensorchord/VectorChord/releases/download/\(version)/postgresql-14-vchord_\(version)_aarch64-linux-gnu.zip"
	}
	sha256: {
		"x86_64-linux":  "a3ad61c47605c29fcb594e51b3068430adefe10841cf844ee6d8c587a7f75ca2"
		"aarch64-linux": "c1fe737f666d20c75b1cffb265b43535b797b24bdf21925275642e892d392764"
	}
	installPhase: """
		mkdir -p "$out/lib" "$out/share/postgresql"
		cp pkglibdir/vchord.so "$out/lib/"
		cp -R sharedir/extension "$out/share/postgresql/"
		"""
}

// initdb's en_US collation needs locale data from the same locked libc snapshot.
let postgresLocales = schema.#PackageSpec & {
	pname: "immich-postgres-locales"
	version: "1.0.0"
	platforms: ["linux"]
	buildInputs: [{pname: "glibc-locales", attr: "glibcLocales", version: "2.42"}]
	buildScript: """
		set -eu
		locale_archive=
		IFS=:
		for locale_lib in ${LIBRARY_PATH:-}; do
			if [ -f "$locale_lib/locale/locale-archive" ]; then
				locale_archive="$locale_lib/locale/locale-archive"
				break
			fi
		done
		unset IFS
		[ -n "$locale_archive" ] || { echo "locked glibc locale archive missing" >&2; exit 1; }
		mkdir -p "$out/lib/locale"
		ln -s "$locale_archive" "$out/lib/locale/locale-archive"
		"""
	exports: LOCALE_ARCHIVE: "$out/lib/locale/locale-archive"
}

// The server they build against: nixpkgs' postgresql drops pg_config and keeps what it
// printed in its dev output (which holds PGXS too). `sysroot` is the SDK the compiler
// wrapper builds with: the server's own build recorded one this machine may not have.
let pgBuildInputs = [
	pkgs.postgresql_14,
	{pname: "postgresql", attr: "postgresql_14.dev", version: "14"},
	{pname: "clang"},
]
let pgConfig = #"""
	dev=
	IFS=:
	for include in ${CPATH:-}; do
		[ -f "${include%/include}/nix-support/pg_config.expected" ] && dev=${include%/include}
	done
	unset IFS
	[ -n "$dev" ] || { echo "no postgresql dev output among the inputs" >&2; exit 1; }
	mkdir -p "$PWD/.pg"
	PG_CONFIG="$PWD/.pg/pg_config"
	cat > "$PG_CONFIG" << SHIM
	#!/bin/sh
	while IFS= read -r line; do
		case "\$line" in PGXS\ =\ *) line="PGXS = $dev/lib/pgxs/src/makefiles/pgxs.mk" ;; esac
		[ \$# -eq 0 ] && { printf '%s\\n' "\$line"; continue; }
		for flag; do
			key=\$(printf %s "\${flag#--}" | tr a-z A-Z)
			case "\$line" in "\$key = "*) printf '%s\\n' "\${line#"\$key = "}" ;; esac
		done
	done < "$dev/nix-support/pg_config.expected"
	SHIM
	chmod +x "$PG_CONFIG"
	sysroot= next=
	for word in $(clang -### -x c -c /dev/null 2>&1); do
		word=${word#\"}; word=${word%\"}
		[ -n "$next" ] && { sysroot=$word; break; }
		[ "$word" = -isysroot ] && next=1
	done
	[ -n "$sysroot" ] || { echo "no -isysroot from clang" >&2; exit 1; }
	"""#

let pgvectorDarwin = schema.#GenericBuildSpec & {
	pname:   "pgvector"
	version: "0.8.1"
	platforms: [schema.#Platform.Darwin]
	src:    "https://github.com/pgvector/pgvector/archive/refs/tags/v\(version).tar.gz"
	sha256: "a9094dfb85ccdde3cbb295f1086d4c71a20db1d26bf1d6c39f07a7d164033eb4"
	buildInputs: list.Concat([pgBuildInputs, [{pname: "gnumake"}]])
	// PGXS with the variables the server's build recorded for its own machine overridden:
	// no -march=native (OPTFLAGS), no JIT bitcode, this SDK.
	buildScript: #"""
		set -eu
		\#(pgConfig)
		flags="PG_CONFIG=$PG_CONFIG PG_SYSROOT=$sysroot CC=clang OPTFLAGS= with_llvm=no"
		make $flags
		make $flags DESTDIR="$PWD/.stage" install
		mkdir -p "$out/lib" "$out/share/postgresql/extension"
		cp "$PWD/.stage$("$PG_CONFIG" --pkglibdir)/vector.so" "$out/lib/"
		cp "$PWD/.stage$("$PG_CONFIG" --sharedir)/extension/"vector* "$out/share/postgresql/extension/"
		"""#
}

// VectorChord publishes no darwin build: built as its CI's psql_macos job does (pgrx,
// cargo build --features pg14), offline from the crates its Cargo.lock names
// (helpers/vchord/crates.cue).
let vchordDarwin = schema.#GenericBuildSpec & {
	pname:   "vchord"
	version: vchord.version
	platforms: [schema.#Platform.Darwin]
	src:    "https://github.com/tensorchord/VectorChord/archive/refs/tags/\(version).tar.gz"
	sha256: "d3045b018ddf22fecbe65e56079e2254869b75f14ed3aa9f7bd0cce81ea727ce"
	fetch:  vchord.crates
	buildInputs: list.Concat([pgBuildInputs, [
		{pname: "rustc"},
		{pname: "cargo"},
		// bindgen's libclang.
		{pname: "libclang", attr: "libclang.lib"},
		{pname: "gnutar"},
		{pname: "gzip"},
		// Rust's std links libiconv, which nixpkgs' SDK leaves out and propagates instead.
		{pname: "apple-sdk"},
	]])
	buildScript: #"""
		set -eu
		\#(pgConfig)
		export PGRX_PG_CONFIG_PATH="$PG_CONFIG"
		# Vendored as `cargo vendor` lays crates out: Cargo.lock's checksum is the .crate's.
		mkdir -p vendor
		env | while IFS='=' read -r key crate; do
			case "$key" in crate_*) ;; *) continue ;; esac
			unpacked=$(mktemp -d)
			tar -xzf "$crate" -C "$unpacked"
			sum=$(sha256sum "$crate")
			for dir in "$unpacked"/*; do
				mv "$dir" vendor/
				printf '{"files":{},"package":"%s"}' "${sum%% *}" > "vendor/${dir##*/}/.cargo-checksum.json"
			done
			rmdir "$unpacked"
		done
		export CARGO_HOME="$PWD/.cargo-home"
		mkdir -p "$CARGO_HOME"
		cat > "$CARGO_HOME/config.toml" << CONFIG
		[source.crates-io]
		replace-with = "vendored"
		[source.vendored]
		directory = "$PWD/vendor"
		CONFIG
		IFS=:
		for lib in ${LIBRARY_PATH:-}; do
			[ -e "$lib/libclang.dylib" ] && export LIBCLANG_PATH="$lib"
		done
		unset IFS
		[ -n "${LIBCLANG_PATH:-}" ] || { echo "no libclang among the inputs" >&2; exit 1; }
		export BINDGEN_EXTRA_CLANG_ARGS="-isysroot $sysroot"
		# Its rust-toolchain.toml pins a nightly for the unstable features it uses; pgrx
		# formats the bindings it generates for reading only.
		export RUSTC_BOOTSTRAP=1 RUSTFMT=true
		cargo build --offline --frozen --release -p vchord --lib --features pg14
		mkdir -p "$out/lib" "$out/share/postgresql/extension"
		cp target/release/libvchord.dylib "$out/lib/vchord.so"
		cp vchord.control sql/install/vchord--"$version".sql sql/upgrade/*.sql \
			"$out/share/postgresql/extension/"
		"""#
}

profiles: dev: schema.#Profile & {
	name: "immich-dev"
	// Upstream's pins (.nvmrc, mise.toml, packageManager, test images), from nixpkgs or, at
	// versions it never shipped, the archives above. tests/conformance.rs checks them
	// against upstream.
	tools: [
		pnpm,
		nodejs,
		pkgs.python & {version: "3.12"},
		ffmpeg,
		uv,
		extismJs,
		binaryen,
		pkgs.valkey & {version: "9"},
		// exiftool-vendored runs perl, which upstream's server image ships and runner
		// images need not.
		{pname: "perl"},
		// download.e2e-spec.ts unzips the archives the server serves.
		{pname: "unzip"},
		{pname: "shellcheck"},
		// The helpers' `#!/usr/bin/env bash` and their locks: macOS ships bash 3.2 (no
		// mapfile; empty arrays fail under `set -u`) and no flock(1).
		{pname: "bash"},
		{pname: "flock"},
		// What the helpers run besides, found by resolving each inside `enve run` (the host's
		// otherwise): build-if-stale.sh's `git` and `sha256sum`, the readiness probes' `curl`,
		// the trace helpers' `awk`.
		{pname: "git"},
		{pname: "curl"},
		{pname: "coreutils"},
		{pname: "gawk"},
		// The immich-server service's start (dropdb/createdb, helpers/start-immich-server.sh)
		// and readiness probe (psql, helpers/immich-server-ready.sh) run on the profile's PATH,
		// not postgres's: declared, the postgres service's join below is the profile's server.
		pkgs.postgresql_14,
		postgresLocales,
		// Playwright's headless Chromium shell from the store (PLAYWRIGHT_BROWSERS_PATH,
		// PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS, FONTCONFIG_FILE), matching
		// pnpm-lock.yaml's @playwright/test 1.64.1.
		pkgs.#PlaywrightBrowsers & {version: "1.64.1", features: ["chromium-headless-shell"]},
	]
	services: {
		// As upstream's test image: PostgreSQL 14 with pgvector and VectorChord, which enve
		// joins into the server the profile runs.
		postgres: {
			name:    "postgres"
			package: pkgs.postgresql_14
			extensions: [pgvector, pgvectorDarwin, vchordLinux, vchordDarwin]
			command: "sh -c helpers/start-postgres.sh"
			// As upstream's e2e compose publishes it (`5435:5432`); a named instance's port
			// reaches e2e/src/utils.ts as ENVE_SERVICE_POSTGRES_PORT (patches/).
			port: 5435
			// A cold start runs initdb before the postmaster listens.
			timeout: "60s"
			environment: {
				TZ:   "UTC"
				PGTZ: "UTC"
			}
			lifecycle: {
				postStart: "createdb -h 127.0.0.1 -p $PORT -U postgres immich 2>/dev/null || true; createdb -h 127.0.0.1 -p $PORT -U postgres mich 2>/dev/null || true; psql -h 127.0.0.1 -p $PORT -U postgres -d immich -c \"CREATE EXTENSION IF NOT EXISTS vector;\" -c \"CREATE EXTENSION IF NOT EXISTS cube;\" || true; psql -h 127.0.0.1 -p $PORT -U postgres -d mich -c \"CREATE EXTENSION IF NOT EXISTS vector;\" -c \"CREATE EXTENSION IF NOT EXISTS cube;\" || true"
			}
		}
		// As upstream's compose (`valkey/valkey:9`). The compose never publishes it, so not
		// 6379: enve adopts whatever already listens on a service's port ("already active:
		// skipping local spawn"), and a host's or another project's redis there became the
		// server's queue.
		valkey: {
			name:    "valkey"
			package: pkgs.valkey & {version: "9"}
			command: "valkey-server --dir \"$DATA_DIR\" --bind 127.0.0.1 --port $PORT --save \"\""
			port:    6385
		}
		"immich-server": {
			name:    "immich-server"
			command: "sh -c helpers/start-immich-server.sh"
			// As upstream's e2e docker-compose; the specs reach a named instance's at
			// PLAYWRIGHT_BASE_URL (patches/).
			port: 2285
			// The metrics listeners IMMICH_TELEMETRY_INCLUDE=all opens (upstream's defaults):
			// slots, so two instances' servers don't race for one port.
			ports: {api_metrics: 8081, microservices_metrics: 8082}
			dependsOn: [{service: "postgres"}, {service: "valkey"}]
			// As upstream's e2e docker-compose (testing mode, no machine learning, all
			// telemetry) and its server image (production node, build metadata from the
			// compose build args).
			environment: {
				IMMICH_ENV:                        "testing"
				IMMICH_MACHINE_LEARNING_ENABLED:   "false"
				IMMICH_TELEMETRY_INCLUDE:          "all"
				NODE_ENV:                          "production"
				IMMICH_BUILD:                      "1234567890"
				IMMICH_BUILD_URL:                  "https://github.com/immich-app/immich/actions/runs/1234567890"
				IMMICH_BUILD_IMAGE:                "e2e"
				IMMICH_BUILD_IMAGE_URL:            "https://github.com/immich-app/immich/pkgs/container/immich-server"
				IMMICH_REPOSITORY:                 "immich-app/immich"
				IMMICH_REPOSITORY_URL:             "https://github.com/immich-app/immich"
				IMMICH_SOURCE_REF:                 "e2e"
				IMMICH_SOURCE_COMMIT:              "e2eeeeeeeeeeeeeeeeee"
				IMMICH_SOURCE_URL:                 "https://github.com/immich-app/immich/commit/e2eeeeeeeeeeeeeeeeee"
				DB_HOSTNAME:                       "127.0.0.1"
				DB_PORT:                           "${ENVE_SERVICE_POSTGRES_PORT}"
				DB_DATABASE_NAME:                  "immich"
				DB_USERNAME:                       "postgres"
				DB_PASSWORD:                       ""
				REDIS_HOSTNAME:                    "127.0.0.1"
				REDIS_PORT:                        "${ENVE_SERVICE_VALKEY_PORT}"
				IMMICH_PORT:                       "$PORT"
				IMMICH_API_METRICS_PORT:           "$PORT_API_METRICS"
				IMMICH_MICROSERVICES_METRICS_PORT: "$PORT_MICROSERVICES_METRICS"
				IMMICH_HOST:                       "127.0.0.1"
				IMMICH_GEODATA_CACHE:              ".enact/cache/immich-geodata"
				IMMICH_IGNORE_MOUNT_CHECK_ERRORS:  "true"
			}
			readinessProbe: {
				// The API answers and the worker has imported geodata (the script says why).
				command: "sh -c helpers/immich-server-ready.sh"
				port:    2285
				// Headroom for building server/dist and web/build, fetching or building
				// helpers/server-image (node, vips, sharp) and running migrations on a cold runner.
				timeout: "300s"
			}
		}
		// As upstream's e2e compose: the oauth specs' provider, built from
		// packages/e2e-auth-server/Dockerfile (`pnpm run start` in the package).
		"e2e-auth-server": {
			name:    "e2e-auth-server"
			command: "sh -c 'cd packages/e2e-auth-server && exec pnpm run start'"
			port:    2286
			readinessProbe: {
				command: "curl -s -f --connect-timeout 1 --max-time 3 http://127.0.0.1:$PORT/.well-known/openid-configuration || exit 1"
				port:    2286
				timeout: "60s"
			}
		}
		"immich-ml": {
			name:    "immich-ml"
			command: "sh -c helpers/start-immich-ml.sh"
			port:    3003
			environment: {
				IMMICH_MACHINE_LEARNING_PORT: "$PORT"
				IMMICH_MACHINE_LEARNING_HOST: "127.0.0.1"
			}
			readinessProbe: {
				command: "curl -s -f --connect-timeout 1 --max-time 3 http://127.0.0.1:$PORT/ping || exit 1"
				port:    3003
				timeout: "60s"
			}
		}
	}
	environment: {
		// `pnpm run` otherwise re-verifies the whole workspace and reinstalls every
		// package a filtered CI install left out (~17s per task on a cold store).
		pnpm_config_verify_deps_before_run: "false"
		TZ:                          "UTC"
		PGTZ:                        "UTC"
		// No container runtime: a docker client (testcontainers, compose) fails here
		// instead of silently starting upstream's images where a runner has docker.
		DOCKER_HOST: "unix:///nonexistent/enact-runs-no-containers.sock"
		// The run's service instance's ports (enact runs each run's services on their own).
		DB_HOSTNAME:              "127.0.0.1"
		DB_PORT:                  "${ENVE_SERVICE_POSTGRES_PORT}"
		DB_DATABASE_NAME:         "immich"
		DB_USERNAME:              "postgres"
		DB_PASSWORD:              ""
		PLAYWRIGHT_BASE_URL:      "${ENVE_SERVICE_IMMICH_SERVER_URL}"
		IMMICH_TEST_POSTGRES_URL: "postgres://postgres:postgres@127.0.0.1:${ENVE_SERVICE_POSTGRES_PORT}/mich"
		// e2e's vitest and Playwright configs otherwise run `docker compose up`
		// (src/docker-compose.ts, playwright.config.ts) when nothing answers on
		// 127.0.0.1:2285: enve runs the services, on any port.
		VITEST_DISABLE_DOCKER_SETUP:  "true"
		PLAYWRIGHT_DISABLE_WEBSERVER: "true"
		// @swc/core 1.16 unpacks its addon into a cache whose every ancestor must be owned
		// by root or the user. In `enve run`'s Linux user namespace root is unmapped, so `/`
		// shows as nobody's and every cache root fails ("a parent writable by another user"):
		// vitest's swc plugin, and every server spec, failed to load.
		SWC_NATIVE_BINDING_CACHE_SKIP_SECURITY_CHECK: "1"
	}
}
