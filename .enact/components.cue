package immich

import "enact.dev/schema"

let J = pipeline.#jobs

_tsComponent: {
	root:             string
	watch_paths:      *["\(root)/**"] | [...string]
	workspace_scope:  {include_dependencies: true, include: *[root] | [...string]}
}

_vitestComponent: _tsComponent & {
	recorder:    "own_linux"
	recorded_by: ["enact-node"]
}

pipeline: schema.#Pipeline & {
	name:        "immich"
	description: "High-performance self-hosted photo and video management solution (enact + enve accelerated)"

	workspace_scope: {
		ignore: [
			".devcontainer", ".dockerignore", ".editorconfig", ".env.*", ".git-blame-ignore-revs",
			".github", ".nvmrc", ".prettierrc", ".vscode", "CODEOWNERS", "CONTRIBUTING.md",
			"deployment", "design", "docker", "docs", "fastlane", "install.sh", "LICENSE",
			"misc", "mise.lock", "mise.toml", ".mise", "readme_i18n", "renovate.json", "**/*.md",
		]
		include: [
			".enact", "cue.mod", "enve.cue", "enve.lock", "bin", "helpers",
			"package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".pnpmfile.cjs", "tsconfig.json", "turbo.json",
		]
	}

	// Build outputs read by traces (rules don't chain: esbuild/vite bundles list @immich/sdk sources too).
	analysis: derived: [
		{outputs: ["packages/sdk/build/**"], inputs: ["packages/sdk/src/**", "packages/sdk/package.json", "packages/sdk/tsconfig.json"]},
		{outputs: ["packages/plugin-sdk/dist/**"], inputs: ["packages/plugin-sdk/src/**", "packages/plugin-sdk/esbuild.js", "packages/plugin-sdk/plugin-sdk.mjs", "packages/plugin-sdk/package.json", "packages/plugin-sdk/tsconfig.json", "packages/sdk/src/**"]},
		{outputs: ["packages/plugin-core/dist/**"], inputs: ["packages/plugin-core/src/**", "packages/plugin-core/esbuild.js", "packages/plugin-core/manifest.json", "packages/plugin-core/package.json", "packages/plugin-core/tsconfig.json", "packages/plugin-sdk/src/**", "packages/sdk/src/**"]},
		{outputs: ["server/dist/**"], inputs: ["server/src/**", "server/nest-cli.json", "server/package.json", "server/tsconfig.json", "server/tsconfig.build.json"], exclude: ["server/src/**/*.spec.ts"], mapped: ["server/src/**"]},
		{outputs: ["packages/cli/dist/**"], inputs: ["packages/cli/src/**", "packages/cli/vite.config.ts", "packages/cli/package.json", "packages/cli/tsconfig.json", "packages/sdk/src/**"]},
		{outputs: ["web/.svelte-kit/tsconfig.json"], inputs: ["web/svelte.config.js"]},
		{
			outputs: ["web/.svelte-kit/*.d.ts", "web/.svelte-kit/generated/**", "web/.svelte-kit/types/**"]
			inputs:  ["web/svelte.config.js", "web/src/routes/**/+*.ts", "web/src/routes/**/+*.js", "web/src/params/**", "web/src/app.html", "web/src/hooks.*", "web/src/service-worker/**"]
			layout:  ["web/src/routes/**"]
		},
		{outputs: ["web/build/**", "web/.svelte-kit/output/**"], inputs: ["web/src/**", "web/static/**", "web/svelte.config.js", "web/vite.config.ts", "web/package.json", "web/tsconfig.json", "i18n/**", "packages/sdk/src/**"]},
		{outputs: ["machine-learning/.venv/**"], inputs: ["machine-learning/pyproject.toml", "machine-learning/uv.lock", "machine-learning/.python-version", "helpers/uv"]},
	]

	caches: {
		geodata:      {paths: [".enact/cache/immich-geodata"], version: "geonames-ne-v5.1.2", used_by: {components: ["e2e"], jobs: [J.test, J.maintenance, J.web]}}
		uv_python:    {paths: [".enact/state/cache/uv-python"], key: ["enve.lock"], scope: "task", used_by: components: ["machine-learning"]}
		python_cache: {paths: ["machine-learning/.pytest_cache", "machine-learning/.ruff_cache"], key: ["machine-learning/pyproject.toml"], scope: "task", used_by: components: ["machine-learning"]}
	}

	components: {
		root: {
			name: "root", title: "Immich Environment & Pipeline", root: "."
			watch_paths: [
				"enve.cue", "enve.lock", "helpers/vchord/**", ".enact/**", "cue.mod/**",
				"helpers/trace/**", ".github/workflows/ci.yml", ".github/workflows/nightly.yml", "bin/linux-x86_64/**", "bin/linux-aarch64/**", "bin/macos-aarch64/**", "bin/enact", "bin/enve",
			]
			depends_on:      []
			workspace_scope: include_dependencies: true
		}

		js_root: {
			name: "js-root", title: "Immich pnpm Workspace", technology: "typescript", root: "."
			watch_paths: [
				"package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "tsconfig.json", "turbo.json",
				".pnpmfile.cjs", "helpers/build-workspace-deps.sh", "helpers/installed-store.cjs",
				"helpers/lint-runner.sh", "helpers/typecheck-runner.sh", "helpers/vitest-runner.sh",
			]
			depends_on:      [components.root]
			workspace_scope: include_dependencies: true
		}

		test_assets: {
			name: "test-assets", title: "Immich Test Assets", root: "e2e/test-assets"
			watch_paths: ["e2e/test-assets", ".gitmodules"]
			depends_on:  [components.root]
		}

		base: _vitestComponent & {
			name: "base", title: "Immich Server Core: API, Schema & Base Models (@immich/server)", root: "server"
			kind: "service", domain: "backend"
			uses: [
				{protocol: schema.#Protocol.Sql, target: "postgres", title: "Stores photo metadata & vector embeddings"},
				{protocol: schema.#Protocol.Redis, target: "valkey", title: "BullMQ job queues & session cache"},
				{protocol: schema.#Protocol.Http, target: "machine-learning", title: "Requests CLIP & facial recognition inference"},
			]
			watch_paths: [
				"server/**", "helpers/schema-check-runner.sh", "helpers/build-core-plugin.sh",
				"helpers/build-if-stale.sh", "helpers/start-postgres.sh", "helpers/start-immich-server.sh",
				"helpers/immich-server-ready.sh", "helpers/provision-geodata.sh",
				"helpers/server-image.cjs", "helpers/server-image.sh", "helpers/server-image/**", "helpers/container/**",
			]
			depends_on:      [components.js_root, components.plugin_core, components.test_assets]
			workspace_scope: submodules: ["e2e/test-assets"]
			services:        [immich.services.postgres, immich.services.valkey]
			service:         immich.services["immich-server"]
			resources:       {cpus: 2, memory_mb: 3072}
			shards:          2
			target_scope:    {fallback: "all", tests: ["server/src/**/*.spec.ts", "server/test/medium/**/*.spec.ts"], rules: [{match: ["server/**/*.ts"], engine: "typescript"}]}
			jobs: {
				lint: {
					direct: true, services: false, resources: {cpus: 2, memory_mb: 1280}
					tasks: [
						{command: "../helpers/lint-runner.sh {relative_changed_files}", filter: {include: ["**/*.{ts,mts,cts,js,mjs,cjs,json,yaml,yml,md,sh}"], on_empty: "skip"}},
						{command: "../helpers/schema-check-runner.sh --order-only", filter: {include: ["server/src/schema/migrations/**"], on_empty: "skip"}},
					]
				}
				typecheck: {direct: true, services: false, resources: {cpus: 2, memory_mb: 3072}, tasks: [{command: "../helpers/typecheck-runner.sh"}]}
				test: {
					needs: ["@immich/sdk:build", "@immich/plugin-sdk:build", "@immich/plugin-core:build"]
					tasks: [{command: "../helpers/vitest-runner.sh {relative_targets}"}]
				}
			}
			migrate: {command: "../helpers/schema-check-runner.sh", filter: {include: ["server/src/schema/**", "server/src/queries/**"], on_empty: "skip"}}
		}

		i18n: _tsComponent & {
			name: "i18n", title: "Immich Translations", root: "i18n"
			depends_on: [components.js_root]
			lint:       {command: "../helpers/lint-runner.sh {relative_changed_files}", filter: {include: ["**/*.json"], on_empty: "skip"}}
		}

		web: _vitestComponent & {
			name: "@immich/web", title: "Immich SvelteKit Web Frontend", root: "web"
			kind: "app", domain: "clients"
			uses: [{protocol: schema.#Protocol.Http, target: "base", title: "Calls REST API via @immich/sdk"}]
			depends_on:        [components.js_root, components.sdk, components.i18n]
			resources:         {cpus: 2, memory_mb: 3072}
			shards:            2
			target_scope:      {fallback: "all", tests: ["web/src/**/*.spec.ts"], rules: [{match: ["web/**/*.{ts,js,svelte}"], engine: "typescript"}]}
			lint:              {command: "../helpers/lint-runner.sh {relative_changed_files}", filter: {include: ["**/*.{ts,mts,cts,js,mjs,cjs,svelte,json,yaml,yml,md}"], on_empty: "skip"}}
			typecheck: command: "../helpers/typecheck-runner.sh"
			jobs: test: {
				needs: ["@immich/sdk:build"]
				tasks: [{command: "../helpers/vitest-runner.sh {relative_targets}"}]
			}
		}

		machine_learning: _tsComponent & {
			name: "machine-learning", title: "Immich Python CLIP & Facial Recognition Service", root: "machine-learning"
			kind: "service", domain: "ml"
			watch_paths:  ["machine-learning/**", "helpers/pytest-runner.sh", "helpers/start-immich-ml.sh", "helpers/uv"]
			depends_on:   [components.root]
			service:      immich.services["immich-ml"]
			target_scope: {fallback: "all", tests: ["machine-learning/test_*.py"], rules: [{match: ["machine-learning/**/*.py"], engine: "python"}]}
			jobs: lint: {
				name: "Lint", direct: true, services: false
				tasks: [
					{name: "Run Linter", command: "../helpers/uv run --extra cpu ruff format --check {relative_changed_files} && ../helpers/uv run --extra cpu ruff check {relative_changed_files}", filter: {include: ["**/*.py"], on_empty: "skip"}},
					{name: "ShellCheck", command: "shellcheck -x {relative_changed_files}", filter: {include: ["**/*.sh"], on_empty: "skip"}},
				]
			}
			typecheck: command: "../helpers/uv run --extra cpu mypy --strict immich_ml/"
			recorder:           "trace"
			test: command:      "../helpers/pytest-runner.sh {relative_targets}"
		}

		plugin_sdk: _tsComponent & {
			name: "@immich/plugin-sdk", title: "Immich Plugin SDK", kind: "library", domain: "sdk", root: "packages/plugin-sdk"
			depends_on:        [components.js_root, components.sdk]
			typecheck: command: "../../helpers/typecheck-runner.sh"
			jobs: build: {
				name: "Build @immich/plugin-sdk", services: false
				needs: ["@immich/sdk:build"]
				outputs: {
					paths: ["packages/plugin-sdk/dist", "packages/plugin-sdk/dist/index.js"]
					key: [
						"packages/plugin-sdk/**", "packages/sdk/**", "helpers/build-workspace-deps.sh",
						"helpers/build-if-stale.sh", "helpers/installed-store.cjs", "package.json",
						"pnpm-lock.yaml", "pnpm-workspace.yaml", ".pnpmfile.cjs", "tsconfig.json", "turbo.json",
					]
				}
				tasks: [{command: "../../helpers/build-workspace-deps.sh --package ./dist/index.js"}]
			}
		}
		plugin_core: _tsComponent & {
			name: "@immich/plugin-core", title: "Immich Core Plugin (wasm)", kind: "library", domain: "sdk", root: "packages/plugin-core"
			depends_on:        [components.js_root, components.sdk, components.plugin_sdk]
			typecheck: command: "../../helpers/typecheck-runner.sh"
			jobs: build: {
				name: "Build @immich/plugin-core", services: false
				needs: ["@immich/sdk:build", "@immich/plugin-sdk:build"]
				outputs: {
					paths: ["packages/plugin-core/dist", "packages/plugin-core/dist/plugin.wasm"]
					key: [
						"packages/plugin-core/**", "packages/plugin-sdk/**", "packages/sdk/**",
						"helpers/build-core-plugin.sh", "helpers/build-if-stale.sh", "helpers/installed-store.cjs",
						"package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".pnpmfile.cjs",
						"tsconfig.json", "turbo.json",
					]
				}
				tasks: [{command: "../../helpers/build-core-plugin.sh --producer"}]
			}
		}
		e2e_auth_server: _tsComponent & {name: "@immich/e2e-auth-server", title: "Immich e2e OAuth Provider", kind: "service", domain: "verification", root: "packages/e2e-auth-server", depends_on: [components.js_root]}
		sdk: _tsComponent & {
			name: "@immich/sdk", title: "Immich OpenAPI Generated TypeScript SDK", kind: "library", domain: "sdk", root: "packages/sdk"
			depends_on:        [components.js_root]
			typecheck: command: "../../helpers/typecheck-runner.sh"
			jobs: build: {
				name: "Build @immich/sdk", services: false
				outputs: {
					paths: ["packages/sdk/build", "packages/sdk/build/index.js"]
					key: [
						"packages/sdk/**", "helpers/build-workspace-deps.sh", "helpers/build-if-stale.sh",
						"helpers/installed-store.cjs", "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml",
						".pnpmfile.cjs", "tsconfig.json", "turbo.json",
					]
				}
				tasks: [{command: "../../helpers/build-workspace-deps.sh --package ./build/index.js"}]
			}
		}

		cli: _vitestComponent & {
			name: "@immich/cli", title: "Immich TypeScript Command Line Interface", root: "packages/cli"
			kind: "app", domain: "clients"
			uses: [{protocol: schema.#Protocol.Http, target: "base", title: "Uploads assets & manages albums via REST API"}]
			depends_on:        [components.js_root, components.sdk]
			target_scope:      {fallback: "all", tests: ["packages/cli/src/**/*.spec.ts"], rules: [{match: ["packages/cli/**/*.ts"], engine: "typescript"}]}
			lint:              {command: "../../helpers/lint-runner.sh {relative_changed_files}", filter: {include: ["**/*.{ts,mts,cts,js,mjs,cjs,json,yaml,yml,md}"], on_empty: "skip"}}
			typecheck: command: "../../helpers/typecheck-runner.sh"
			jobs: test: {
				needs: ["@immich/sdk:build"]
				tasks: [{command: "../../helpers/vitest-runner.sh {relative_targets}"}]
			}
		}

		scripts: _vitestComponent & {
			name: "@immich/scripts", title: "Immich Release Scripts", root: "packages/scripts"
			depends_on:    [components.js_root]
			target_scope:  {fallback: "all", tests: ["packages/scripts/src/**/*.spec.ts"], rules: [{match: ["packages/scripts/**/*.ts"], engine: "typescript"}]}
			lint:          {command: "../../helpers/lint-runner.sh {relative_changed_files}", filter: {include: ["**/*.{ts,mts,cts,js,mjs,cjs,json,yaml,yml,md}"], on_empty: "skip"}}
			test: command: "../../helpers/vitest-runner.sh {relative_targets}"
		}

		openapi: _tsComponent & {
			name: "@immich/openapi", title: "Immich OpenAPI Specifications", root: "open-api"
			watch_paths: [
				"open-api/**", "helpers/openapi-drift-runner.sh", "server/src/bin/sync-open-api.ts",
				"server/src/controllers/**", "server/src/dtos/**", "server/src/decorators.ts",
				"server/src/constants.ts", "server/src/enum.ts", "server/src/utils/misc.ts",
			]
			depends_on:      [components.js_root, components.plugin_sdk]
			workspace_scope: include: ["open-api", "packages/sdk/src", "server"]
			lint: command:   "../helpers/openapi-drift-runner.sh"
		}

		native: {name: "native", title: "Immich Native Core (Rust)", kind: "library", domain: "clients", root: "native", watch_paths: ["native/**"], depends_on: [components.root]}
		mobile: _tsComponent & {
			name: "@immich/mobile", title: "Immich Mobile Application", kind: "app", domain: "clients", root: "mobile"
			uses: [{protocol: schema.#Protocol.Http, target: "base", title: "Syncs media & albums via REST API"}]
			depends_on: [components.root, components.openapi, components.native]
		}

		e2e: _tsComponent & {
			name: "e2e", title: "Immich End-to-End Full Stack Integration", kind: "verification", domain: "verification", root: "e2e"
			watch_paths:        ["e2e/**", "helpers/playwright-runner.sh", "helpers/prepare-e2e-builds.sh"]
			depends_on:         [components.base, components.cli, components.plugin_core, components.web, components.e2e_auth_server, components.test_assets]
			services:           [immich.services.postgres, immich.services.valkey, immich.services["immich-server"], immich.services["e2e-auth-server"]]
			workspace_scope:    submodules: ["e2e/test-assets"]
			resources:          {cpus: 4, memory_mb: 8192}
			target_scope:       {fallback: "none", tests: ["e2e/src/specs/server/**/*.e2e-spec.ts"], rules: [{match: ["e2e/**/*.ts", "server/**/*.ts"], engine: "typescript"}]}
			lint:               {command: "../helpers/lint-runner.sh {relative_changed_files}", filter: {include: ["**/*.{ts,mts,cts,js,mjs,cjs,json,yaml,yml,md}"], on_empty: "skip"}}
			typecheck: command: "../helpers/typecheck-runner.sh"
			jobs: {
				build: {
					name: "Build E2E dependencies", services: false, resources: {cpus: 4, memory_mb: 8192}
					needs: ["@immich/sdk:build", "@immich/plugin-sdk:build", "@immich/plugin-core:build"]
					outputs: {
						paths: [
							"server/dist", "server/dist/main.js", "web/build", "web/build/index.html",
							"packages/cli/dist", "packages/cli/dist/index.js", "e2e/node_modules/.enact-deps-stamp",
						]
						key: [
							"server/**", "web/**", "i18n/**", "packages/sdk/**", "packages/plugin-sdk/**",
							"packages/plugin-core/**", "packages/cli/**", "packages/e2e-auth-server/**",
							"e2e/package.json", "helpers/prepare-e2e-builds.sh", "helpers/build-if-stale.sh",
							"helpers/installed-store.cjs", "helpers/build-workspace-deps.sh",
							"helpers/build-core-plugin.sh", "helpers/server-image.sh", "helpers/server-image/**",
							"package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".pnpmfile.cjs",
							"tsconfig.json", "turbo.json",
						]
					}
					tasks: [{command: "../helpers/prepare-e2e-builds.sh"}]
				}
				test: {needs: ["build", "@immich/sdk:build", "@immich/plugin-sdk:build", "@immich/plugin-core:build"], recorder: "trace", resources: {cpus: 4, memory_mb: 8192}, tasks: [{command: "../helpers/vitest-runner.sh {relative_targets}"}]}
				maintenance: {
					name: "Server Maintenance E2E", needs: ["build", "@immich/sdk:build", "@immich/plugin-sdk:build", "@immich/plugin-core:build"], recorder: "trace", resources: {cpus: 4, memory_mb: 8192}
					target_scope: {fallback: "none", default_target: "src/specs/maintenance/server", tests: ["e2e/src/specs/maintenance/server/**/*.e2e-spec.ts"], rules: [{match: ["e2e/**/*.ts", "server/**/*.ts"], engine: "typescript"}]}
					tasks: [{name: "Server Maintenance E2E", command: "../helpers/vitest-runner.sh {relative_targets}"}]
				}
				web: {
					name: "Web E2E", needs: ["build", "@immich/sdk:build", "@immich/plugin-sdk:build", "@immich/plugin-core:build"], recorder: "trace", resources: {cpus: 4, memory_mb: 8192}
					target_scope: {
						fallback: "none"
						tests:    ["e2e/src/specs/web/**/*.e2e-spec.ts", "e2e/src/ui/specs/**/*.e2e-spec.ts", "e2e/src/specs/maintenance/web/**/*.e2e-spec.ts"]
						rules:    [{match: ["e2e/**/*.ts", "web/**/*.{ts,svelte}", "server/**/*.ts"], engine: "typescript"}]
					}
					tasks: [{name: "Web E2E", command: "../helpers/playwright-runner.sh {relative_targets}"}]
				}
			}
		}
	}
}
