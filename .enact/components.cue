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
			// mise's installs of mise.toml's `npm:` tools (.mise/locks/<tool>/<version>).
			".mise",
			"readme_i18n",
			"renovate.json",
			"**/*.md",
		]
		include: [
			".enact",
			"cue.mod",
			"enve.cue",
			"enve.lock",
			"bin",
			"helpers",
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
		// tsc, sourceMap on: the e2e specs' server functions are placed in server/src.
		mapped: ["server/src/**"]
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
	}, {
		// `vite build`: the build the e2e server serves, and svelte-kit's output before it.
		// The 167 server specs list the repository as vitest starts, these directories too.
		outputs: ["web/build/**", "web/.svelte-kit/output/**"]
		inputs: [
			"web/src/**", "web/static/**", "web/svelte.config.js", "web/vite.config.ts",
			"web/package.json", "web/tsconfig.json", "i18n/**", "packages/sdk/src/**",
		]
	}, {
		// The environment helpers/uv syncs for the ML jobs.
		outputs: ["machine-learning/.venv/**"]
		inputs: [
			"machine-learning/pyproject.toml", "machine-learning/uv.lock",
			"machine-learning/.python-version", "helpers/uv",
		]
	}]

	// No build outputs (server/dist, web/build, packages/*/dist): the helpers build them
	// when missing, so a cache keyed on the lockfile restored the base branch's server
	// into every PR (STALE_BUILD_OUTPUT_CACHE). Each job builds from its own checkout.
	caches: {
		// GeoNames + Natural Earth for the e2e server's reverse geocoding (~50MB download).
		geodata: {
			paths: [".enact/cache/immich-geodata"]
			version: "geonames-ne-v5.1.2"
			used_by: {components: ["e2e"], jobs: [J.test, J.web]}
		}
		// The interpreters helpers/uv downloads, one directory per uv store object.
		uv_python: {
			paths: [".enact/state/cache/uv-python"]
			key: ["enve.lock"]
			scope: "task"
			used_by: components: ["machine-learning"]
		}
		python_cache: {
			paths: [
				"machine-learning/.pytest_cache",
				"machine-learning/.ruff_cache",
			]
			key: ["machine-learning/pyproject.toml"]
			scope: "task"
			used_by: components: ["machine-learning"]
		}
	}

	components: {
		// What every component runs with: the environment and the pipeline. Files only
		// some components use belong to them, or to js_root when several share them.
		root: {
			name:  "root"
			title: "Immich Environment & Pipeline"
			root:  "."
			watch_paths: [
				"enve.cue",
				"enve.lock",
				// enve.cue's VectorChord crates (darwin builds it from source).
				"helpers/vchord/**",
				".enact/**",
				"cue.mod/**",
				// Records the reach map of every suite.
				"helpers/trace/**",
				// The workflow enact generates (upstream's are removed in the fork).
				".github/workflows/ci.yml",
				// The enact and enve builds the fork commits for its CI (scripts/fork-push.sh).
				"bin/linux-x86_64/**",
				"bin/linux-aarch64/**",
			]
			depends_on: []
			workspace_scope: {
				include_dependencies: true
			}
		}

		// The pnpm workspace every JavaScript package installs and runs its checks from.
		js_root: {
			name:  "js-root"
			title: "Immich pnpm Workspace"
			// The packages depending on it get the pnpm install.
			technology: "typescript"
			root:       "."
			watch_paths: [
				"package.json",
				"pnpm-lock.yaml",
				"pnpm-workspace.yaml",
				"tsconfig.json",
				"turbo.json",
				// Shapes installs.
				".pnpmfile.cjs",
				"helpers/build-workspace-deps.sh",
				"helpers/lint-runner.sh",
				"helpers/typecheck-runner.sh",
				"helpers/vitest-runner.sh",
			]
			depends_on: [components.root]
			workspace_scope: {
				include_dependencies: true
			}
			// No lint job: nothing upstream lints the workspace's own files (its lockfile isn't
			// prettier's); its `format` script checks only i18n/, the i18n component's.
		}

		// Upstream's media fixtures (the e2e/test-assets submodule): the server's medium exif
		// specs and the e2e server read them, so a submodule bump runs both.
		test_assets: {
			name:  "test-assets"
			title: "Immich Test Assets"
			root:  "e2e/test-assets"
			// The gitlink names the directory whole (a literal path names everything below it).
			watch_paths: ["e2e/test-assets", ".gitmodules"]
			depends_on: [components.root]
		}

		// The core (`@immich/server`): the data kernel and base models, i.e. the schema and
		// migrations, the repositories, the DTOs the OpenAPI spec is generated from. Its unit
		// and medium specs are the core tests; the resources and services (postgres, valkey)
		// are allocated around them.
		base: {
			name:  "base"
			title: "Immich Server Core: API, Schema & Base Models (@immich/server)"
			root:  "server"
			watch_paths: [
				"server/**",
				// Its migrations check, its core plugin build and its services: postgres and
				// the server in the image's container view (the e2e server too).
				"helpers/schema-check-runner.sh",
				"helpers/build-core-plugin.sh",
				"helpers/build-if-stale.sh",
				"helpers/start-postgres.sh",
				"helpers/start-immich-server.sh",
				"helpers/immich-server-ready.sh",
				"helpers/provision-geodata.sh",
				"helpers/server-image.cjs",
				"helpers/server-image.sh",
				"helpers/server-image/**",
				"helpers/container/**",
			]
			// The medium workflow specs run the core plugin, as upstream's `server` change
			// filter (`packages/plugin-core/**`, `packages/plugin-sdk/**`).
			depends_on: [components.js_root, components.plugin_core, components.test_assets]
			workspace_scope: {
				include_dependencies: true
				// Its workspace packages (plugin-sdk, plugin-core, sdk) come with its dependencies.
				include: ["server"]
				// The medium exif specs read fixture media (server/test/medium.factory.ts).
				submodules: ["e2e/test-assets"]
			}
			services: [immich.services.postgres, immich.services.valkey]
			service: immich.services["immich-server"]
			// Per shard: vitest-runner.sh runs one worker per CPU (ENACT_SHARD_WORKERS).
			resources: {cpus: 2, memory_mb: 3072}
			shards:    2
			target_scope: {
				fallback: "all"
				// As helpers/trace/generate-reach-map.sh traces them.
				tests: ["server/src/**/*.spec.ts", "server/test/medium/**/*.spec.ts"]
				rules: [{
					match: ["server/**/*.ts"]
					engine: "typescript"
				}]
			}
			// Its bin/*.sh get upstream's ShellCheck job's check.
			jobs: {
				lint: {
					direct:   true
					services: false
					resources: {cpus: 2, memory_mb: 1280}
					tasks: [{
						command: "../helpers/lint-runner.sh {relative_changed_files}"
						filter: {
							include: ["**/*.{ts,mts,cts,js,mjs,cjs,json,yaml,yml,md,sh}"]
							on_empty: "skip"
						}
					}]
				}
				typecheck: {
					direct:   true
					services: false
					resources: {cpus: 2, memory_mb: 3072}
					tasks: [{command: "../helpers/typecheck-runner.sh"}]
				}
			}
			migrate: {
				command: "../helpers/schema-check-runner.sh"
				filter: {
					include: ["server/src/schema/**", "server/src/queries/**"]
					on_empty: "skip"
				}
			}
			// vitest-runner.sh records, with the functions each file ran (helpers/trace/footprints.sh, Linux).
			recorder: "own_linux"
			recorded_by: ["enact-node"]
			test: {
				command: "../helpers/vitest-runner.sh {relative_targets}"
			}
		}

		// The translations: upstream's `i18n` change filter runs its "Test i18n" job (the root's
		// prettier with its sort-json plugin, `pnpm format:fix` left clean), and its `web` filter
		// names them too: the web build and its specs read them.
		i18n: {
			name:  "i18n"
			title: "Immich Translations"
			root:  "i18n"
			watch_paths: ["i18n/**"]
			// The root's prettier and its plugin.
			depends_on: [components.js_root]
			workspace_scope: {
				include_dependencies: true
				include: ["i18n"]
			}
			// lint-runner.sh runs the root's `format` (prettier --check i18n/) on the changed files.
			lint: {
				command: "../helpers/lint-runner.sh {relative_changed_files}"
				filter: {
					include: ["**/*.json"]
					on_empty: "skip"
				}
			}
		}

		web: {
			name:  "@immich/web"
			title: "Immich SvelteKit Web Frontend"
			root:  "web"
			watch_paths: ["web/**"]
			depends_on: [components.js_root, components.sdk, components.i18n]
			workspace_scope: {
				include_dependencies: true
				include: ["web"]
			}
			// Per shard: vitest-runner.sh runs one worker per CPU (ENACT_SHARD_WORKERS).
			resources: {cpus: 2, memory_mb: 3072}
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
					include: ["**/*.{ts,mts,cts,js,mjs,cjs,svelte,json,yaml,yml,md}"]
					on_empty: "skip"
				}
			}
			typecheck: {
				command: "../helpers/typecheck-runner.sh"
			}
			// vitest-runner.sh records, with the functions each file ran (helpers/trace/footprints.sh, Linux).
			recorder: "own_linux"
			recorded_by: ["enact-node"]
			test: {
				command: "../helpers/vitest-runner.sh {relative_targets}"
			}
		}

		machine_learning: {
			name:  "machine-learning"
			title: "Immich Python CLIP & Facial Recognition Service"
			root:  "machine-learning"
			watch_paths: [
				"machine-learning/**",
				"helpers/pytest-runner.sh",
				"helpers/start-immich-ml.sh",
				"helpers/uv",
			]
			depends_on: [components.root]
			workspace_scope: {
				include_dependencies: true
				include: ["machine-learning"]
			}
			service: immich.services["immich-ml"]
			target_scope: {
				fallback: "all"
				tests: ["machine-learning/test_*.py"]
				rules: [{
					match: ["machine-learning/**/*.py"]
					engine: "python"
				}]
			}
			// As upstream's machine-learning/mise.toml `ci-unit` (with its pinned uv) and
			// static_analysis.yml's ShellCheck on its shell scripts.
			jobs: lint: {
				name:     "Lint"
				direct:   true
				services: false
				tasks: [{
					name:    "Run Linter"
					command: "../helpers/uv run --extra cpu ruff format --check {relative_changed_files} && ../helpers/uv run --extra cpu ruff check {relative_changed_files}"
					filter: {
						include: ["**/*.py"]
						on_empty: "skip"
					}
				}, {
					name:    "ShellCheck"
					command: "shellcheck -x {relative_changed_files}"
					filter: {
						include: ["**/*.sh"]
						on_empty: "skip"
					}
				}]
			}
			typecheck: {
				command: "../helpers/uv run --extra cpu mypy --strict immich_ml/"
			}
			recorder: "trace"
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
			depends_on: [components.js_root, components.sdk]
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
			depends_on: [components.js_root, components.sdk, components.plugin_sdk]
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
			depends_on: [components.js_root]
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
			// Its client is committed, not generated at build: a spec change alone is drift,
			// which @immich/openapi's lint catches. Upstream's filters run no web, server or
			// cli job on `open-api/**` either.
			depends_on: [components.js_root]
			workspace_scope: {
				include_dependencies: true
				include: ["packages/sdk"]
			}
			// No lint job: the package has no lint or format script, nor an ESLint config.
			typecheck: {
				command: "../../helpers/typecheck-runner.sh"
			}
		}

		cli: {
			name:  "@immich/cli"
			title: "Immich TypeScript Command Line Interface"
			root:  "packages/cli"
			watch_paths: ["packages/cli/**"]
			depends_on: [components.js_root, components.sdk]
			workspace_scope: {
				include_dependencies: true
				include: ["packages/cli"]
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
					include: ["**/*.{ts,mts,cts,js,mjs,cjs,json,yaml,yml,md}"]
					on_empty: "skip"
				}
			}
			typecheck: {
				command: "../../helpers/typecheck-runner.sh"
			}
			// vitest-runner.sh records, with the functions each file ran (helpers/trace/footprints.sh, Linux).
			recorder: "own_linux"
			recorded_by: ["enact-node"]
			test: {
				command: "../../helpers/vitest-runner.sh {relative_targets}"
			}
		}

		// Upstream's release tooling.
		scripts: {
			name:  "@immich/scripts"
			title: "Immich Release Scripts"
			root:  "packages/scripts"
			watch_paths: ["packages/scripts/**"]
			depends_on: [components.js_root]
			workspace_scope: {
				include_dependencies: true
				include: ["packages/scripts"]
			}
			target_scope: {
				fallback: "all"
				tests: ["packages/scripts/src/**/*.spec.ts"]
				rules: [{
					match: ["packages/scripts/**/*.ts"]
					engine: "typescript"
				}]
			}
			// Upstream's `script-unit-tests` only (`pnpm --filter @immich/scripts test`): the
			// package declares neither typescript nor eslint.
			// vitest-runner.sh records, with the functions each file ran (helpers/trace/footprints.sh, Linux).
			recorder: "own_linux"
			recorded_by: ["enact-node"]
			test: {
				command: "../../helpers/vitest-runner.sh {relative_targets}"
			}
		}

		openapi: {
			name:  "@immich/openapi"
			title: "Immich OpenAPI Specifications"
			root:  "open-api"
			watch_paths: ["open-api/**"]
			depends_on: [components.js_root]
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

		// The Rust image core the mobile app links (native_core_ffi). Upstream's
		// `native-tests` job (cargo fmt, clippy, test at native/mise.toml's Rust) has no
		// showcased job: immich's env has no Rust.
		native: {
			name:  "native"
			title: "Immich Native Core (Rust)"
			root:  "native"
			watch_paths: ["native/**"]
			depends_on: [components.root]
		}

		mobile: {
			name:  "@immich/mobile"
			title: "Immich Mobile Application"
			root:  "mobile"
			watch_paths: ["mobile/**"]
			// Its `codegen:native` builds native_core_ffi and binds its header (mobile/mise.toml).
			depends_on: [components.root, components.openapi, components.native]
			workspace_scope: {
				include_dependencies: true
				include: ["mobile"]
			}
		}

		e2e: {
			name:  "e2e"
			title: "Immich End-to-End Full Stack Integration"
			root:  "e2e"
			watch_paths: [
				"e2e/**",
				"helpers/playwright-runner.sh",
			]
			// Its server runs the core plugin and serves the web build, as the image ships
			// them (start-immich-server.sh); the oauth specs sign in at e2e-auth-server.
			depends_on: [components.base, components.cli, components.plugin_core, components.web, components.e2e_auth_server, components.test_assets]
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
				// The vitest server suite; the Playwright web specs run in `jobs.web`.
				tests: ["e2e/src/specs/server/**/*.e2e-spec.ts"]
				rules: [{
					match: ["e2e/**/*.ts"]
					engine: "typescript"
				}]
			}
			// As upstream's e2e/mise.toml `ci-unit` (`format`, `lint`, `check`).
			lint: {
				command: "../helpers/lint-runner.sh {relative_changed_files}"
				filter: {
					include: ["**/*.{ts,mts,cts,js,mjs,cjs,json,yaml,yml,md}"]
					on_empty: "skip"
				}
			}
			typecheck: {
				command: "../helpers/typecheck-runner.sh"
			}
			// The specs import the built SDK and drive the built CLI: vitest-runner.sh builds
			// them first (helpers/build-workspace-deps.sh), as upstream's e2e job does, and put
			// the `docker` the specs exec into the server on PATH (helpers/container/path).
			test: {
				command: "../helpers/vitest-runner.sh {relative_targets}"
			}
			// No recorder of its own (footprints.sh leaves the e2e package out): enact traces
			// each wanted spec alone (`enact trace run`, Linux), the job's services as its
			// own, so a change to the server (its service footprint) reaches every spec.
			recorder: "trace"
			// Upstream's `e2e-tests-web`: the Playwright web, ui and maintenance suites.
			jobs: web: {
				name: "Web E2E"
				recorder: "trace"
				target_scope: {
					fallback: "all"
					tests: [
						"e2e/src/specs/web/**/*.e2e-spec.ts",
						"e2e/src/ui/specs/**/*.e2e-spec.ts",
						"e2e/src/specs/maintenance/web/**/*.e2e-spec.ts",
					]
					rules: [{
						match: ["e2e/**/*.ts", "web/**/*.{ts,svelte}"]
						engine: "typescript"
					}]
				}
				tasks: [{
					name:    "Web E2E"
					command: "../helpers/playwright-runner.sh {relative_targets}"
				}]
			}
		}
	}
}
