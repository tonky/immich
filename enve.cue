package enve

import (
	"github.com/tonky/enve/schema/v1:schema"
	"github.com/tonky/enve/pkgs:pkgs"
)

profiles: dev: schema.#Profile & {
	name: "immich-dev"
	// Upstream's pins (.nvmrc, mise.toml, packageManager, test images); the ones nixpkgs
	// never shipped are in tools.lock. tests/conformance.rs checks both against upstream.
	tools: [
		// Self-switches to `packageManager` (pnpm@11.22.0) in the repository.
		pkgs.pnpm & {version: "12"},
		// A nixos-unstable revision with 24.15.0 whose closure cache.nixos.org has.
		pkgs.nodejs & {version: "24.15.0", rev: "709bea2ee399733c738e38565677620c9e7461b8"},
		pkgs.python & {version: "3.11"},
		// As upstream's test images (`immich-app/postgres:14-vectorchord0.4.3`); its pgvector
		// and vchord are in tools.lock.
		pkgs.postgresql_14,
		pkgs.valkey & {version: "9"},
		// exiftool-vendored runs perl, which upstream's server image ships and runner
		// images need not.
		{pname: "perl"},
		{pname: "shellcheck"},
	]
	services: {
		postgres: {
			name:    "postgres"
			package: pkgs.postgresql_14
			command: "sh -c helpers/start-postgres.sh"
			// As upstream's e2e compose publishes it (`5435:5432`): e2e/src/utils.ts connects there.
			port: 5435
			// A cold start fetches the pinned extensions, links the prefix and runs initdb
			// before the postmaster listens.
			timeout: "60s"
			environment: {
				TZ:   "UTC"
				PGTZ: "UTC"
			}
			lifecycle: {
				postStart: "createdb -h 127.0.0.1 -p 5435 -U postgres immich 2>/dev/null || true; createdb -h 127.0.0.1 -p 5435 -U postgres mich 2>/dev/null || true; psql -h 127.0.0.1 -p 5435 -U postgres -d immich -c \"CREATE EXTENSION IF NOT EXISTS vector;\" -c \"CREATE EXTENSION IF NOT EXISTS cube;\" || true; psql -h 127.0.0.1 -p 5435 -U postgres -d mich -c \"CREATE EXTENSION IF NOT EXISTS vector;\" -c \"CREATE EXTENSION IF NOT EXISTS cube;\" || true"
			}
		}
		// As upstream's compose (`valkey/valkey:9`).
		valkey: {
			name:    "valkey"
			package: pkgs.valkey & {version: "9"}
			command: "valkey-server --dir \"$DATA_DIR\" --port 6379 --save \"\""
		}
		"immich-server": {
			name:    "immich-server"
			command: "sh -c helpers/start-immich-server.sh"
			// As upstream's e2e docker-compose: the cli specs expect 127.0.0.1:2285.
			port: 2285
			dependsOn: [{service: "postgres"}, {service: "valkey"}]
			// As upstream's e2e docker-compose (testing mode, no machine learning, all
			// telemetry) and its server image (production node, build metadata from the
			// compose build args).
			environment: {
				IMMICH_ENV:                       "testing"
				IMMICH_MACHINE_LEARNING_ENABLED:  "false"
				IMMICH_TELEMETRY_INCLUDE:         "all"
				NODE_ENV:                         "production"
				IMMICH_BUILD:                     "1234567890"
				IMMICH_BUILD_URL:                 "https://github.com/immich-app/immich/actions/runs/1234567890"
				IMMICH_BUILD_IMAGE:               "e2e"
				IMMICH_BUILD_IMAGE_URL:           "https://github.com/immich-app/immich/pkgs/container/immich-server"
				IMMICH_REPOSITORY:                "immich-app/immich"
				IMMICH_REPOSITORY_URL:            "https://github.com/immich-app/immich"
				IMMICH_SOURCE_REF:                "e2e"
				IMMICH_SOURCE_COMMIT:             "e2eeeeeeeeeeeeeeeeee"
				IMMICH_SOURCE_URL:                "https://github.com/immich-app/immich/commit/e2eeeeeeeeeeeeeeeeee"
				DB_HOSTNAME:                      "127.0.0.1"
				DB_PORT:                          "5435"
				DB_DATABASE_NAME:                 "immich"
				DB_USERNAME:                      "postgres"
				DB_PASSWORD:                      ""
				REDIS_HOSTNAME:                   "127.0.0.1"
				REDIS_PORT:                       "6379"
				IMMICH_PORT:                      "2285"
				IMMICH_HOST:                      "127.0.0.1"
				IMMICH_GEODATA_CACHE:             ".enact/cache/immich-geodata"
				IMMICH_IGNORE_MOUNT_CHECK_ERRORS: "true"
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
				command: "curl -s -f --connect-timeout 1 --max-time 3 http://127.0.0.1:2286/.well-known/openid-configuration || exit 1"
				port:    2286
				timeout: "60s"
			}
		}
		"immich-ml": {
			name:    "immich-ml"
			command: "sh -c helpers/start-immich-ml.sh"
			port:    3003
			environment: {
				IMMICH_MACHINE_LEARNING_PORT: "3003"
				IMMICH_MACHINE_LEARNING_HOST: "127.0.0.1"
			}
			readinessProbe: {
				command: "curl -s -f --connect-timeout 1 --max-time 3 http://127.0.0.1:3003/ping || exit 1"
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
		DOCKER_HOST:                 "unix:///nonexistent/enact-runs-no-containers.sock"
		DB_HOSTNAME:                 "127.0.0.1"
		DB_PORT:                     "5435"
		DB_DATABASE_NAME:            "immich"
		DB_USERNAME:                 "postgres"
		DB_PASSWORD:                 ""
		REDIS_HOSTNAME:              "127.0.0.1"
		REDIS_PORT:                  "6379"
		IMMICH_SERVER_URL:           "http://127.0.0.1:2285"
		PLAYWRIGHT_BASE_URL:         "http://127.0.0.1:2285"
		IMMICH_TEST_POSTGRES_URL:    "postgres://postgres:postgres@127.0.0.1:5435/mich"
	}
}
