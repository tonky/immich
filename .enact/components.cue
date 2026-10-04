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

	// Build outputs the traces read: no diff names them, so a change to their sources
	// reaches their readers only through these. Rules don't chain: the plugin bundles
	// (esbuild) inline @immich/sdk, so they list its sources too. `.svelte-kit/tsconfig.json`
	// has its own rule: 167 server specs read only it (tsconfig discovery). svelte-kit sync
	// reads route modules (`+page.ts`: load types) but only lists `.svelte` routes, so
	// those are `layout`: adding or deleting one regenerates `.svelte-kit`, editing doesn't.
	analysis: derived: [{
		outputs: ["packages/sdk/build/**"]
		inputs: ["packages/sdk/src/**", "packages/sdk/package.json", "packages/sdk/tsconfig.json"]
	}, {
		outputs: ["packages/plugin-sdk/dist/**"]
		inputs: [
			"packages/plugin-sdk/src/**", "packages/plugin-sdk/esbuild.js", "packages/plugin-sdk/plugin-sdk.mjs",
			"packages/plugin-sdk/package.json", "packages/plugin-sdk/tsconfig.json", "packages/sdk/src/**",
		]
	}, {
		outputs: ["packages/plugin-core/dist/**"]
		inputs: [
			"packages/plugin-core/src/**", "packages/plugin-core/esbuild.js", "packages/plugin-core/manifest.json",
			"packages/plugin-core/package.json", "packages/plugin-core/tsconfig.json",
			"packages/plugin-sdk/src/**", "packages/sdk/src/**",
		]
	}, {
		// `nest build`: immich-admin (`docker exec`) runs it inside the e2e specs' tree.
		outputs: ["server/dist/**"]
		inputs: [
			"server/src/**", "server/nest-cli.json", "server/package.json", "server/tsconfig.json",
			"server/tsconfig.build.json",
		]
	}, {
		// `vite build` bundles the cli with everything it imports, the sdk included.
		outputs: ["packages/cli/dist/**"]
		inputs: [
			"packages/cli/src/**", "packages/cli/vite.config.ts", "packages/cli/package.json",
			"packages/cli/tsconfig.json", "packages/sdk/src/**",
		]
	}, {
		outputs: ["web/.svelte-kit/tsconfig.json"]
		inputs: ["web/svelte.config.js"]
	}, {
		outputs: ["web/.svelte-kit/*.d.ts", "web/.svelte-kit/generated/**", "web/.svelte-kit/types/**"]
		inputs: [
			"web/svelte.config.js", "web/src/routes/**/+*.ts", "web/src/routes/**/+*.js",
			"web/src/params/**", "web/src/app.html", "web/src/hooks.*", "web/src/service-worker/**",
		]
		layout: ["web/src/routes/**"]
	}]

	// No build outputs (server/dist, web/build, packages/*/dist): the helpers build them
	// when missing, so a cache keyed on the lockfile restored the base branch's server
	// into every PR (STALE_BUILD_OUTPUT_CACHE). Each job builds from its own checkout.
	caches: {
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

		// The oauth specs' provider (the e2e-auth-server service); upstream runs no checks
		// of its own.
		e2e_auth_server: {
			name:  "@immich/e2e-auth-server"
			title: "Immich e2e OAuth Provider"
			root:  "packages/e2e-auth-server"
			watch_paths: ["packages/e2e-auth-server/**"]
			depends_on: [components.root]
			workspace_scope: {
				include_dependencies: true
				include: ["packages/e2e-auth-server"]
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
			// Its server runs the core plugin and serves the web build, as the image ships
			// them (start-immich-server.sh); the oauth specs sign in at e2e-auth-server.
			depends_on: [components.server, components.cli, components.plugin_core, components.web, components.e2e_auth_server]
			// The server specs run against the real server with machine learning
			// disabled, as upstream's docker-compose does.
			services: [
				immich.services.postgres,
				immich.services.valkey,
				immich.services["immich-server"],
				immich.services["e2e-auth-server"],
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
			// them first (helpers/build-workspace-deps.sh), as upstream's e2e job does, and put
			// the `docker` the specs exec into the server on PATH (helpers/container/path).
			test: {
				command: "../helpers/vitest-runner.sh {relative_targets}"
			}
		}
	}
}
