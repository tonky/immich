package immich

import (
	"enact.dev/schema"
	"immich.app:enve"
)

immich: services: enve.profiles.dev.services

immich: services: {
	postgres: enact: kind: "postgres"
	valkey: enact: kind:   "redis"
	"immich-server": enact: kind: "http"
	"e2e-auth-server": enact: kind: "http"
	"immich-ml": enact: kind: "http"
}

pipeline: schema.#Pipeline & {
	services: immich.services
}
