package immich

import (
	"enact.dev/schema"
	"immich.app:enve"
)

let J = pipeline.#jobs

immich: services: enve.profiles.dev.services & {
	postgres: enact: kind: "postgres"
	valkey: enact: kind:   "redis"
	"immich-server": enact: {kind: "http", node_functions: true}
	"e2e-auth-server": enact: kind: "http"
	"immich-ml": enact: kind: "http"
}

pipeline: schema.#Pipeline & {
	services: immich.services
	toolchain: node: package_manager: "pnpm"
	ci: {
		no_cache: {labels: ["no-cache", "showcase"], branch_prefixes: ["showcase/"]}
		concurrency: max_parallel_jobs: 16
		remote_cache: {
			secrets: {bucket: "R2_BUCKET", access_key_id: "R2_ACCESS_KEY_ID", secret_access_key: "R2_SECRET_ACCESS_KEY"}
			public_url: "https://pub-30fd937eb7634039b8c49d49bfec91a9.r2.dev"
			public_key: "enve-r2-1:ckHPTeWVef6mba+1AwWHjKYCsUWKPfP9IXPm5YXNoHg="
			repo:       "tonky/immich"
			branch:     "perf/ci-modernization"
		}
		budget: {enforce: true, untraced_tests: 55, wall_minutes: 30}
		workers: {
			standard: {
				labels: ["self-hosted", "Linux", "X64", "tonky-ci"], tier: "dedicated", available: 1, cost_per_min: 0.010
				pool: {
					cpus: 14, memory_mb: 28672
					sizes: {
						"tonky-ci-s": {cpus: 2, memory_mb: 4096}
						"tonky-ci-m": {cpus: 4, memory_mb: 8192}
						"tonky-ci-l": {cpus: 6, memory_mb: 13312}
					}
				}
			}
			arm64: {
				labels: ["self-hosted", "Linux", "ARM64", "tonky-ci"], tier: "dedicated", available: 1, cost_per_min: 0.008
				pool: {
					cpus: 4, memory_mb: 8192
					sizes: {
						"tonky-ci-s": {cpus: 2, memory_mb: 4096}
						"tonky-ci-m": {cpus: 4, memory_mb: 8192}
					}
				}
			}
		}
	}
	workflows: {
		ci: {
			layout: "staged", services: "on_demand"
			concurrency: {scope: "branch", cancel_in_progress: true}
			triggers: {
				push: branches:         ["main", "master", "perf/ci-modernization"]
				pull_request: branches: ["main", "master", "perf/ci-modernization"]
			}
			stages: [
				{name: "check-and-lint", select: [J.lint, J.typecheck, J.migrate], fail_fast: true, services: "on_demand"},
				{name: "test", matrix: true, select: [J.test, J.maintenance, J.web], fail_fast: false, services: "on_demand"},
			]
		}
		local: {services: "on_demand", stages: [{name: "dev", select: [J.test]}]}
	}
}
