package immich

import (
	"enact.dev/schema"
	"immich.app:enve"
)

immich: services: enve.profiles.dev.services

immich: services: {
	postgres: enact: kind: "postgres"
	valkey: enact: kind:   "redis"
	// The server's Node threads serve coverage windows: each e2e spec is credited with the
	// server functions its requests ran (docs/IMPLEMENTATION.md "Recorders").
	"immich-server": enact: {kind: "http", node_functions: true}
	"e2e-auth-server": enact: kind: "http"
	"immich-ml": enact: kind: "http"
}

pipeline: schema.#Pipeline & {
	services: immich.services
}
