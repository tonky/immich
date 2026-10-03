package immich

import "enact.dev/schema"

let J = pipeline.#jobs

pipeline: schema.#Pipeline & {
	toolchain: node: {
		package_manager: "pnpm"
	}
	ci: {
		no_cache: {
			labels: ["no-cache", "showcase"]
			branch_prefixes: ["showcase/"]
		}
		concurrency: {
			max_parallel_jobs: 16
		}
		workers: {
			"standard": {
				available:    8
				cost_per_min: 0.008
				cpus:         4.0
				labels: [
					"ubuntu-latest",
				]
				memory_mb: 14336
			}
		}
	}
	workflows: {
		ci: {
			layout:   "staged"
			services: "on_demand"
			concurrency: {
				scope:              "branch"
				cancel_in_progress: true
			}
			triggers: {
				push: {
					branches: ["main", "master", "perf/ci-modernization", "showcase/**"]
				}
				pull_request: {
					branches: ["main", "master", "perf/ci-modernization"]
				}
			}
			stages: [
				{
					name: "check-and-lint"
					select: [J.lint, J.typecheck, J.migrate]
					fail_fast: true
					services:  "on_demand"
				},
				{
					name:   "test"
					matrix: true
					select: [J.test]
					fail_fast: false
					services:  "on_demand"
				},
			]
		}
	}
}
