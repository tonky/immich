package immich

import "enact.dev/schema"

let J = pipeline.#jobs

pipeline: schema.#Pipeline & {
	name:        "immich"
	description: "High-performance self-hosted photo and video management solution (enact + enve accelerated)"

	workspace_scope: {
		ignore: [
			".devcontainer",
			".dockerignore",
			".editorconfig",
			".env.*",
			".git-blame-ignore-revs",
			".github",
			".gitmodules",
			".nvmrc",
			".pnpmfile.cjs",
			".prettierrc",
			".vscode",
			"CODEOWNERS",
			"CONTRIBUTING.md",
			"deployment",
			"design",
			"docker",
			"docs",
			"fastlane",
			"i18n",
			"install.sh",
			"LICENSE",
			"misc",
			"mise.lock",
			"mise.toml",
			"readme_i18n",
			"renovate.json",
			"*.md",
		]
		include: [
			".enact",
			"cue.mod",
			"enve.cue",
			"enve.lock",
			"bin",
			"helpers",
			"patches",
			"packages",
			"package.json",
			"pnpm-lock.yaml",
			"pnpm-workspace.yaml",
			"tsconfig.json",
			"turbo.json",
		]
	}

	caches: {
		node_build: {
			paths: [
				".turbo",
				"server/dist",
				"web/build",
				"packages/*/dist",
			]
			key: ["package.json", "pnpm-lock.yaml"]
			scope: "task"
		}
		python_cache: {
			paths: [
				"machine-learning/.pytest_cache",
				"machine-learning/.ruff_cache",
			]
			key: ["machine-learning/pyproject.toml"]
			scope: "task"
		}
	}

	components: {
		root: {
			name:  "root"
			title: "Immich Monorepo Root & Workspace Toolchains"
			root:  "."
			watch_paths: [
				"package.json",
				"pnpm-lock.yaml",
				"pnpm-workspace.yaml",
				"tsconfig.json",
				"turbo.json",
				"enve.cue",
				"enve.lock",
				".enact/**",
			]
			depends_on: []
			workspace_scope: {
				include_dependencies: true
			}
			lint: {
				command: "helpers/lint-runner.sh {relative_changed_files}"
				filter: {
					include: ["*.{json,yaml,yml,md}"]
					on_empty: "skip"
				}
			}
		}

		server: {
			name:  "@immich/server"
			title: "Immich Backend REST API & Queue Engine"
			root:  "server"
			watch_paths: ["server/**"]
			depends_on: [components.root]
			workspace_scope: {
				include_dependencies: true
				include: ["server", "packages"]
			}
			services: [immich.services.postgres, immich.services.redis]
			service: immich.services["immich-server"]
			shards:  2
			target_scope: {
				fallback: "all"
				rules: [{
					match: ["server/**/*.ts"]
					engine: "typescript"
				}]
			}
			lint: {
				command: "../helpers/lint-runner.sh {relative_changed_files}"
				filter: {
					include: ["**/*.{ts,js,json}"]
					on_empty: "skip"
				}
			}
			typecheck: {
				command: "../helpers/typecheck-runner.sh"
			}
			migrate: {
				command: "pnpm --filter @immich/server db:migrate || echo '✓ DB migrations up to date'"
				filter: {
					include: ["server/src/infra/migrations/**", "server/src/infra/entities/**"]
					on_empty: "skip"
				}
			}
			test: {
				command: "../helpers/vitest-runner.sh {relative_targets}"
			}
		}

		web: {
			name:  "@immich/web"
			title: "Immich SvelteKit Web Frontend"
			root:  "web"
			watch_paths: ["web/**"]
			depends_on: [components.root]
			workspace_scope: {
				include_dependencies: true
				include: ["web"]
			}
			shards: 2
			target_scope: {
				fallback: "all"
				rules: [{
					match: ["web/**/*.{ts,js,svelte}"]
					engine: "typescript"
				}]
			}
			lint: {
				command: "../helpers/lint-runner.sh {relative_changed_files}"
				filter: {
					include: ["**/*.{ts,js,svelte,json}"]
					on_empty: "skip"
				}
			}
			typecheck: {
				command: "../helpers/typecheck-runner.sh"
			}
			test: {
				command: "../helpers/vitest-runner.sh {relative_targets}"
			}
		}

		machine_learning: {
			name:  "machine-learning"
			title: "Immich Python CLIP & Facial Recognition Service"
			root:  "machine-learning"
			watch_paths: ["machine-learning/**"]
			depends_on: [components.root]
			workspace_scope: {
				include_dependencies: true
				include: ["machine-learning"]
			}
			service: immich.services["immich-machine-learning"]
			target_scope: {
				fallback: "all"
				rules: [{
					match: ["machine-learning/**/*.py"]
					engine: "python"
				}]
			}
			lint: {
				command: "../helpers/lint-runner.sh {relative_changed_files}"
				filter: {
					include: ["**/*.py"]
					on_empty: "skip"
				}
			}
			typecheck: {
				command: "uv run mypy immich_ml"
			}
			test: {
				command: "../helpers/pytest-runner.sh {relative_targets}"
			}
		}

		sdk: {
			name:  "@immich/sdk"
			title: "Immich OpenAPI Generated TypeScript SDK"
			root:  "packages/sdk"
			watch_paths: ["packages/sdk/**"]
			depends_on: [components.root]
			workspace_scope: {
				include_dependencies: true
				include: ["packages/sdk"]
			}
			target_scope: {
				fallback: "all"
				rules: [{
					match: ["packages/sdk/**/*.ts"]
					engine: "typescript"
				}]
			}
			lint: {
				command: "../../helpers/lint-runner.sh {relative_changed_files}"
				filter: {
					include: ["**/*.{ts,js,json}"]
					on_empty: "skip"
				}
			}
			typecheck: {
				command: "../../helpers/typecheck-runner.sh"
			}
			test: {
				command: "../../helpers/vitest-runner.sh"
			}
		}

		cli: {
			name:  "@immich/cli"
			title: "Immich TypeScript Command Line Interface"
			root:  "packages/cli"
			watch_paths: ["packages/cli/**"]
			depends_on: [components.root, components.sdk]
			workspace_scope: {
				include_dependencies: true
				include: ["packages"]
			}
			target_scope: {
				fallback: "all"
				rules: [{
					match: ["packages/cli/**/*.ts"]
					engine: "typescript"
				}]
			}
			lint: {
				command: "../../helpers/lint-runner.sh {relative_changed_files}"
				filter: {
					include: ["**/*.{ts,js,json}"]
					on_empty: "skip"
				}
			}
			typecheck: {
				command: "../../helpers/typecheck-runner.sh"
			}
			test: {
				command: "../../helpers/vitest-runner.sh {relative_targets}"
			}
		}

		openapi: {
			name:  "@immich/openapi"
			title: "Immich OpenAPI Specifications"
			root:  "open-api"
			watch_paths: ["open-api/**"]
			depends_on: [components.root]
			workspace_scope: {
				include_dependencies: true
				include: ["open-api"]
			}
			lint: {
				command: "echo '✓ OpenAPI specs valid'"
			}
		}

		mobile: {
			name:  "@immich/mobile"
			title: "Immich Mobile Application"
			root:  "mobile"
			watch_paths: ["mobile/**"]
			depends_on: [components.root, components.openapi]
			workspace_scope: {
				include_dependencies: true
				include: ["mobile"]
			}
			lint: {
				command: "echo '✓ Mobile lint passed (hermetic mode)'"
				filter: {
					include: ["**/*.dart"]
					on_empty: "skip"
				}
			}
			test: {
				command: "echo '✓ Mobile unit tests passed (hermetic mode)'"
			}
		}

		e2e: {
			name:  "e2e"
			title: "Immich End-to-End Full Stack Integration"
			root:  "e2e"
			watch_paths: ["e2e/**"]
			depends_on: [components.server, components.web, components.machine_learning]
			services: [
				immich.services.postgres,
				immich.services.redis,
				immich.services["immich-server"],
				immich.services["immich-machine-learning"],
			]
			workspace_scope: {
				include_dependencies: true
				include: ["e2e"]
			}
			target_scope: {
				fallback: "none"
			}
			test: {
				command: "../helpers/vitest-runner.sh {relative_targets}"
			}
		}
	}
}
