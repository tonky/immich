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
		// The fork's jobs run on the user's tonky-ci fleet, one fresh container per job (enact's
		// .enact/workflows.cue workers `tonky-ci`, `tonky-ci-arm64`): stage jobs on the x86_64
		// slots, matrix rows on the cheapest slot they fit, so small ones take the arm64 slot.
		workers: {
			"standard": {
				labels: ["self-hosted", "Linux", "X64", "tonky-ci"]
				tier:         "dedicated"
				available:    2
				cost_per_min: 0.010
				cpus:         6
				memory_mb:    13312
			}
			"arm64": {
				labels: ["self-hosted", "Linux", "ARM64", "tonky-ci"]
				tier:         "dedicated"
				available:    1
				cost_per_min: 0.008
				cpus:         4
				memory_mb:    8192
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
				// Showcase branches run through their pull request only, not twice.
				push: {
					branches: ["main", "master", "perf/ci-modernization"]
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
					select: [J.test, J.web]
					fail_fast: false
					services:  "on_demand"
				},
			]
		}
	}
}
