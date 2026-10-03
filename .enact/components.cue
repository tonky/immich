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
			".prettierrc",
			".vscode",
			"CODEOWNERS",
			"CONTRIBUTING.md",
			"deployment",
			"design",
			"docker",
			"docs",
			"fastlane",
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
			"tools.lock",
			"bin",
			"helpers",
			"patches",
			"packages",
			"package.json",
			"pnpm-lock.yaml",
			"pnpm-workspace.yaml",
			".pnpmfile.cjs",
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
				"packages/sdk/build",
			]
			key: ["package.json", "pnpm-lock.yaml"]
			scope: "task"
		}
		// GeoNames + Natural Earth for the e2e server's reverse geocoding (~50MB download).
		geodata: {
			paths: [".enact/cache/immich-geodata"]
			version: "geonames-ne-v5.1.2"
			used_by: {components: ["e2e"], jobs: [J.test]}
		}
		// helpers/pinned-tool.sh's downloads (jellyfin-ffmpeg, the postgres extensions, uv,
		// extism-js, binaryen). Per task: each fetches only the tools it runs.
		pinned_tools: {
			paths: [".enact/cache/tools"]
			key: ["tools.lock"]
			scope: "task"
			used_by: components: ["@immich/server", "machine-learning", "e2e"]
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
				"tools.lock",
				".enact/**",
				// Shape installs and every job's commands.
				".pnpmfile.cjs",
				"helpers/**",
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
			// The medium workflow specs run the core plugin, as upstream's `server` change
			// filter (`packages/plugin-core/**`, `packages/plugin-sdk/**`).
			depends_on: [components.root, components.plugin_core]
			workspace_scope: {
				include_dependencies: true
				include: ["server", "packages"]
				// The medium exif specs read fixture media (server/test/medium.factory.ts).
				submodules: ["e2e/test-assets"]
			}
			services: [immich.services.postgres, immich.services.valkey]
			service: immich.services["immich-server"]
			shards:  2
			target_scope: {
				fallback: "all"
				// As helpers/trace/generate-reach-map.sh traces them.
				tests: ["server/src/**/*.spec.ts", "server/test/medium/**/*.spec.ts"]
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
				command: "../helpers/schema-check-runner.sh"
				filter: {
					include: ["server/src/schema/**", "server/src/queries/**"]
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
			watch_paths: ["web/**", "i18n/**"]
			depends_on: [components.root, components.sdk]
			workspace_scope: {
				include_dependencies: true
				include: ["web", "i18n"]
			}
			shards: 2
			target_scope: {
				fallback: "all"
				tests: ["web/src/**/*.spec.ts"]
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
			service: immich.services["immich-ml"]
			target_scope: {
				fallback: "all"
				rules: [{
					match: ["machine-learning/**/*.py"]
					engine: "python"
				}]
			}
			// As upstream's machine-learning/mise.toml `ci-unit`, with its pinned uv.
			lint: {
				command: "../helpers/uv run --extra cpu ruff format --check {relative_changed_files} && ../helpers/uv run --extra cpu ruff check {relative_changed_files}"
				filter: {
					include: ["**/*.py"]
					on_empty: "skip"
				}
			}
			typecheck: {
				command: "../helpers/uv run --extra cpu mypy --strict immich_ml/"
			}
			test: {
				command: "../helpers/pytest-runner.sh {relative_targets}"
			}
		}

		// Built for the server (helpers/build-core-plugin.sh), as upstream's `//:plugins`;
		// upstream runs no checks of their own.
		plugin_sdk: {
			name:  "@immich/plugin-sdk"
			title: "Immich Plugin SDK"
			root:  "packages/plugin-sdk"
			watch_paths: ["packages/plugin-sdk/**"]
			depends_on: [components.root, components.sdk]
			workspace_scope: {
				include_dependencies: true
				include: ["packages/plugin-sdk"]
			}
		}

		plugin_core: {
			name:  "@immich/plugin-core"
			title: "Immich Core Plugin (wasm)"
			root:  "packages/plugin-core"
			watch_paths: ["packages/plugin-core/**"]
			depends_on: [components.root, components.sdk, components.plugin_sdk]
			workspace_scope: {
				include_dependencies: true
				include: ["packages/plugin-core"]
			}
		}

		sdk: {
			name:  "@immich/sdk"
			title: "Immich OpenAPI Generated TypeScript SDK"
			root:  "packages/sdk"
			watch_paths: ["packages/sdk/**"]
			depends_on: [components.root, components.openapi]
			workspace_scope: {
				include_dependencies: true
				include: ["packages/sdk"]
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
				tests: ["packages/cli/src/**/*.spec.ts"]
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
				include: ["open-api", "packages/sdk/src"]
			}
			// Upstream's `open-api-typescript` drift check: the committed TypeScript client
			// must be what the committed spec generates.
			lint: {
				command: "pnpm dlx oazapfts@7.5.0 --optimistic --argumentStyle=object --useEnumType --allSchemas immich-openapi-specs.json ../packages/sdk/src/fetch-client.ts && git diff --exit-code -- ../packages/sdk/src/fetch-client.ts"
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
		}

		e2e: {
			name:  "e2e"
			title: "Immich End-to-End Full Stack Integration"
			root:  "e2e"
			watch_paths: ["e2e/**"]
			// Its server runs the core plugin, as the image ships it (start-immich-server.sh).
			depends_on: [components.server, components.cli, components.plugin_core]
			// The server specs run against the real server with machine learning
			// disabled, as upstream's docker-compose does.
			services: [
				immich.services.postgres,
				immich.services.valkey,
				immich.services["immich-server"],
			]
			workspace_scope: {
				include_dependencies: true
				include: ["e2e"]
				submodules: ["e2e/test-assets"]
			}
			target_scope: {
				fallback: "none"
				// The vitest server suite; the Playwright web specs beside it are not run.
				tests: ["e2e/src/specs/server/**/*.e2e-spec.ts"]
				rules: [{
					match: ["e2e/**/*.ts"]
					engine: "typescript"
				}]
			}
			// The specs import the built SDK and drive the built CLI: vitest-runner.sh builds
			// them first (helpers/build-workspace-deps.sh), as upstream's e2e job does.
			test: {
				command: "../helpers/vitest-runner.sh {relative_targets}"
			}
		}
	}
}
