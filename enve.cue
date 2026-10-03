package enve

import (
	"github.com/tonky/enve/schema/v1:schema"
	"github.com/tonky/enve/pkgs:pkgs"
)

profiles: dev: schema.#Profile & {
	name: "immich-dev"
	tools: [
		pkgs.pnpm & {version: "12"},
		pkgs.nodejs & {version: "22"},
		pkgs.python & {version: "3.11"},
		pkgs.postgresql,
		pkgs.redis,
	]
	services: {
		postgres: {
			name:    "postgres"
			command: "helpers/start-postgres.sh"
			environment: {
				TZ:   "UTC"
				PGTZ: "UTC"
			}
			lifecycle: {
				postStart: "createdb -h 127.0.0.1 -p 5432 -U postgres immich 2>/dev/null || true; createdb -h 127.0.0.1 -p 5432 -U postgres mich 2>/dev/null || true; psql -h 127.0.0.1 -p 5432 -U postgres -d immich -c \"CREATE EXTENSION IF NOT EXISTS vector;\" -c \"CREATE EXTENSION IF NOT EXISTS cube;\" || true; psql -h 127.0.0.1 -p 5432 -U postgres -d mich -c \"CREATE EXTENSION IF NOT EXISTS vector;\" -c \"CREATE EXTENSION IF NOT EXISTS cube;\" || true"
			}
		}
		redis: {
			name:    "redis"
			command: "redis-server --dir \"$DATA_DIR\" --port 6379 --save \"\""
		}
		"immich-server": {
			name:    "immich-server"
			command: "helpers/start-immich-server.sh"
			port:    3001
			dependsOn: [{service: "postgres"}, {service: "redis"}]
			environment: {
				NODE_ENV:         "test"
				DB_HOSTNAME:      "127.0.0.1"
				DB_PORT:          "5432"
				DB_DATABASE_NAME: "immich"
				DB_USERNAME:      "postgres"
				DB_PASSWORD:      ""
				REDIS_HOSTNAME:   "127.0.0.1"
				REDIS_PORT:       "6379"
				IMMICH_PORT:      "3001"
				IMMICH_HOST:      "127.0.0.1"
			}
			readinessProbe: {
				command: "curl -s -f --connect-timeout 1 --max-time 3 http://127.0.0.1:3001/api/server-info/ping || exit 1"
				port:    3001
				timeout: "60s"
			}
		}
		"immich-machine-learning": {
			name:    "immich-machine-learning"
			command: "helpers/start-immich-ml.sh"
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
		TZ:                          "UTC"
		PGTZ:                        "UTC"
		DB_HOSTNAME:                 "127.0.0.1"
		DB_PORT:                     "5432"
		DB_DATABASE_NAME:            "immich"
		DB_USERNAME:                 "postgres"
		DB_PASSWORD:                 ""
		REDIS_HOSTNAME:              "127.0.0.1"
		REDIS_PORT:                  "6379"
		IMMICH_MACHINE_LEARNING_URL: "http://127.0.0.1:3003"
	}
}
