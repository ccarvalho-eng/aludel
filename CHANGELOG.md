# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added
- Add validated local, AWS S3, and GCS storage configuration to the standalone release

### Security
- Remove the Docker Compose PostgreSQL host port and require an operator-supplied database password
- Require nonblank HTTP Basic Authentication credentials before the standalone production endpoint starts
- Compare standalone Basic Authentication credentials with Plug's constant-time verifier
- Enforce resolver read-only decisions server-side for all dashboard mutation and model-request events
- Render persisted prompt tags as text instead of reparsing them as HTML
- Isolate PDF conversion in private workspaces and process groups, with bounded input, output, diagnostics, execution time, and ImageMagick resources
- Bound regular expression assertion size, matching work, recursion depth, and wall-clock time
- Reject provider credentials in persisted configuration, remove legacy credential keys, and sanitize runtime and callback boundaries

### Fixed
- Move curated Unreleased entries into the versioned changelog section during release preparation
- Make Hex release reruns recover interrupted GitHub releases and documentation publication safely

### Changed
- Add repeatable quality gates for high-signal code smells, compile cycles, duplicate code, documentation coverage, dependency advisories, and static analysis

## [0.6.1] - 2026-09-04

### Security
- Require Mint 1.10 or later to address HTTP/1 response parsing denial-of-service vulnerabilities in earlier releases

### Changed
- Expanded the README and HexDocs with a complete feature catalog, task-oriented evaluation examples, and embedded deployment guidance
- Reorganized the project wiki into dedicated feature pages covering runs, suites, datasets, analytics, exports, storage, embedding, and demo data
- Updated root and standalone dependency locks, including current ReqLLM, Ecto SQL, and Telemetry Metrics releases

## [0.6.0] - 2026-08-30

### Added
- Added first-class xAI, Groq, and OpenRouter execution, credential configuration, model discovery, provider forms, and demo coverage
- Added deterministic local demo data with reusable datasets, evaluation suites, AI-like results, failures, artifacts, and 60 days of prompt and provider comparison history

### Changed
- Limited provider model selectors to chat and text-generation models so image, speech, transcription, and embedding-only catalog entries are not offered
- Expanded the demo catalog to 14 provider configurations spanning OpenAI, Anthropic, Google Gemini, Ollama, xAI, Groq, and OpenRouter

### Fixed
- Aligned the dataset selector and Add entries button in evaluation suites

## [0.5.2] - 2026-08-30

### Fixed
- Kept prompt version history in a dedicated right-hand rail beside prompt details on tablet and desktop layouts

## [0.5.1] - 2026-08-30

### Security
- Updated the standalone dependency lock to Postgrex 0.22.4, Req 0.7.4, Mint 1.9.3, and Tesla 1.21.2, including compatible Finch and DBConnection updates
- Extended automated dependency scanning to cover the standalone Mix project and frontend npm dependencies

### Changed
- Moved CI and container asset builds from end-of-life Node.js 20 to Node.js 24 LTS
- Rebuilt committed frontend bundles from the current sources

## [0.5.0] - 2026-08-30

### Added
- Pluggable evaluation metrics and persisted structured execution artifacts
- Reusable single-turn and multi-turn datasets with CSV and JSON imports, provenance, idempotent suite imports, filtering, deletion, and complete LiveView workflows
- Rolling 7-day and 30-day dashboard comparisons with weighted quality, exact cost and latency efficiency, pass-rate stability, and bounded regression signals
- Suite-scoped Pareto frontier analysis across quality, cost, and latency trade-offs
- Arbitrary side-by-side prompt version comparisons
- Failure-grounded prompt reflections with variable preservation, explicit human acceptance or dismissal, and immutable accepted versions

### Changed
- Prompt evolution now uses bounded, constant-count queries and reports efficiency and regression signals overall and by provider
- Suite runs now persist exact cost and latency totals plus sample counts, including backfills and retry-safe recalculation
- Updated Phoenix to 1.8.12, Phoenix LiveView to 1.2.10, Req to 0.7.3, and related transitive dependencies

## [0.4.2] - 2026-08-15

### Added
- CSV and JSON test case imports with validation, preview, row-level errors, and persisted suite test cases
- Side-by-side prompt version diffs for reviewing template changes
- Pass-rate, cost, and latency deltas across prompt versions and providers
- A headless `mix aludel.eval` task that runs a suite, emits machine-readable JSON, and returns a failing exit status when the evaluation does not pass

### Changed
- Updated Phoenix, LiveView, Ecto, Req, ReqLLM, LLM DB, Tailwind, and related transitive dependencies, including security fixes
- Automated release metadata preparation and verification for GitHub and Hex publishing
- Excluded generated Dialyzer cache files from the Hex package

## [0.4.1] - 2026-06-15

### Changed
- Refined the README package header with centered branding and the project logo
- Updated `phoenix_live_view` to 1.2.1, `phoenix` to 1.8.8, `req` to 0.6.1, `req_llm` to 1.16.0, `llm_db` to 2026.6.2, `tailwind` to 0.5.0, and related transitive dependencies
- Updated the Codecov GitHub Action to v7

### Fixed
- Suite metadata editing now uses a stable form id for Phoenix LiveView 1.2 form recovery checks

## [0.4.0] - 2026-05-30

### Added
- Prompt evolution metrics can now be exported as JSON or CSV, including version-level aggregates and provider breakdowns

### Changed
- Refined README package presentation and updated the install snippet for the current release line
- Updated `ecto` and `ecto_sql` to 3.14.0, `phoenix_live_view` to 1.1.30, `postgrex` to 0.22.2, `req` to 0.5.18, `req_llm` to 1.12.0, `llm_db` to 2026.5.1, and `ex_doc` to 0.40.3

### Fixed
- Prompt evolution CSV exports now quote control characters and neutralize spreadsheet formula prefixes in text fields

## [0.3.0] - 2026-05-17

### Added
- Embedded callback execution mode for running Aludel evaluations through a host application's real LLM workflow
- Suite creation now supports attaching test case documents before the suite is saved

### Changed
- Run and suite screens now expose execution mode context and preserve callback metadata in exports
- Updated `req_llm` to 1.11.0, `llm_db` to 2026.4.8, Phoenix to 1.8.7, Ecto to 3.13.6, Postgrex to 0.22.1, and ExAws to 2.7.0

### Fixed
- Ollama providers no longer send an authentication marker when no API key is configured
- Suite creation and editing now surface test case persistence failures instead of silently dropping failed test cases

## [0.2.1] - 2026-05-02

### Added
- Raw JSON export for runs and suite runs, including assertion details and suite metadata
- `json_deep_compare` assertions for scoring structured output matches with configurable thresholds

### Changed
- Prompt evolution and suite run summaries now track average structured-output scores
- Run result handling now supports missing cost and latency metrics when providers omit them
- Refined Hex-facing README branding and package presentation
- Updated `llm_db` to 2026.4.6

## [0.2.0] - 2026-04-25

### Added
- Configurable document storage backends for uploaded test case documents, including local, AWS S3, and Google Cloud Storage adapters
- Retry actions for individual suite test results

### Changed
- Modeled explicit run execution states across runs and run results for clearer execution lifecycle tracking
- Updated `req_llm` to 1.10.0

## [0.1.19] - 2026-04-19

### Added
- Copy actions for run and suite results
- Provider pricing now supports built-in defaults with per-provider override support

### Changed
- Refined the provider pricing form and related provider management flow

### Fixed
- SuiteLive now recovers more safely after task crashes
- JSON field assertions now compare scalar values with the correct type handling
- Assertion validation now stays consistent between the visual and JSON editors

## [0.1.18] - 2026-04-12

### Fixed
- Corrected the README dashboard screenshot URL to point at the image on `main`, so it renders reliably on GitHub and Hex.pm

## [0.1.17] - 2026-04-12

### Changed
- Moved run execution into a supervised executor and optimized live run result updates for lower UI refresh overhead
- Refined the Hex-facing README with clearer positioning, setup guidance, and package presentation updates

### Fixed
- Suite prompt previews now stay in sync with the selected prompt version

## [0.1.16] - 2026-04-09

### Added
- Google Gemini provider support, including provider tests and model handling updates

### Changed
- Extracted suite editor assertion parsing, document ingestion, and test-case editing workflows out of `SuiteLive.Show`
- Added a README table of contents and clarified Req / ReqLLM usage guidance

## [0.1.15] - 2026-04-07

### Added
- Provider model handling now supports custom and deprecated models

### Changed
- Replaced native app selects with a shared custom select component for consistent styling and behavior across LiveView forms
- Provider creation and suite run forms now update model choices dynamically based on the selected provider

## [0.1.14] - 2026-04-07

### Changed
- Standardized LiveView form handling across run, provider, and suite flows for more consistent state management and test coverage
- Split dashboard statistics into focused activity, cost, latency, and overview modules to simplify maintenance
- Refined Hex-facing package presentation with improved README/logo rendering and the missing docs files included in releases

### Fixed
- Prompt index filters now apply before pagination, preserve project selections, and keep filtered state stable across navigation
- Prompt versioning now handles edge cases more safely within the prompts context workflow
- Dashboard stats now use suite execution costs and correct activity window boundaries
- Suite pages now refresh prompt projects more reliably and keep assertion remove controls aligned

## [0.1.13] - 2026-04-03

### Added
- Project organization for prompts and evaluation suites, including typed projects and suite assignment flows
- Docker Compose workflow and standalone container setup documentation

### Changed
- Refined suite pages and shared page widths/button layouts for more consistent UI spacing
- Corrected README guidance for provider PDF support
- CI now enforces coverage thresholds and skips Codecov uploads on forked pull requests

### Fixed
- Failed async run executions now log structured errors with configured metadata
- Evolution provider breakdown no longer incurs an N+1 query

## [0.1.12] - 2026-04-01

### Added
- Comprehensive test coverage for LiveView pages (Suite, Provider, Evolution)
- Tests for Evals context functions (preloading, statistics)
- FileValidation and DocumentConverter test coverage
- Web helpers test coverage for routing edge cases
- LlmStubs module for organized test responses
- Generic interfaces README documenting adapter pattern

### Changed
- Consolidated LLM and DocumentConverter under `lib/aludel/interfaces/`
- Renamed `Adapter` behaviour to `Behaviour` for consistency
- Improved adapter config to handle both module and keyword list formats
- CodeCov threshold set to 0% (enforces strict 75% minimum)
- Test coverage improved to 75.2% (up from 71.1%)

### Fixed
- OpenAI PDF handling: Chat API now converts PDFs to images (only Anthropic
  supports native PDFs)
- Mox usage in concurrent tests (switched from expect to stub)
- Excluded router.ex and hooks.ex from coverage reporting

## [0.1.11] - 2026-03-30

### Added
- Interactive tag chips for prompt tags with add/remove functionality
- Version history timeline sidebar for prompts
- Evolution breakdown sidebar with detailed metrics per version and provider

## [0.1.10] - 2026-03-30

### Added
- Pass rates by prompt now expandable from Success Rate stat card

### Changed
- Simplified provider icon helper to use enum pattern matching
- Improved table spacing in dashboard breakdowns for better readability

## [0.1.9] - 2026-03-30

### Added
- Dashboard trend indicators showing 7-day comparison for total runs
- Cost per run metric on dashboard
- Latency percentiles (P50, P95) alongside average latency
- Activity chart showing last 30 days of run history with interactive tooltips
- Cost breakdown by provider and by prompt with toggle view
- Latency breakdown by provider
- Provider icons for Gemini, Grok, Perplexity, Google AI Studio, and OpenAI

### Changed
- Dashboard breakdowns are now collapsible/expandable
- Improved stat card tooltip clarity

### Performance
- Optimized dashboard metrics calculation to reduce database queries

## [0.1.8] - 2026-03-29

### Added
- Visual/JSON toggle for assertion editors on suite pages
- Dynamic field switching for json_field assertion type
- Side-by-side layout for run configuration page with template preview

### Fixed
- Phoenix.PubSub supervisor now properly started in application tree

## [0.1.7] - 2026-03-28

### Added
- Visual test case editor with inline editing of variables and assertions
- File attachment support for test cases (PDF, PNG, JPEG, JSON, CSV, TXT)
- Document support for evaluation suites across OpenAI, Anthropic, and Ollama
- JSON field assertion type for validating structured LLM outputs
- Inline editing for suite name and prompt on suite show page
- OpenAI GPT-4o and Anthropic Claude 4.5 providers in seed data

### Changed
- Improved suite index with more prominent edit actions

### Fixed
- Claude 4.x model support for vision/document capabilities

## [0.1.6] - 2026-03-28

### Changed
- Updated library logo

## [0.1.5] - 2026-03-28

### Added
- Provider icons displayed in providers index (OpenAI, Anthropic, Ollama)
- CSS filter to improve Ollama icon visibility in dark mode

### Fixed
- Provider icons now served via `/images/*` route through Assets plug

## [0.1.4] - 2026-03-27

### Fixed
- Convert markdown badges to HTML to fix rendering on Hex.pm

## [0.1.3] - 2026-03-27

### Fixed
- Remove fixed dimensions from screenshot to prevent squeezing on Hex.pm

## [0.1.2] - 2026-03-27

### Fixed
- Fix README image and badge URLs to work on Hex.pm by using absolute GitHub URLs

## [0.1.1] - 2026-03-27

### Fixed
- Include entire `priv/` directory in Hex package to ensure migrations are available for `mix aludel.install`

## [0.1.0] - 2026-03-27

### Added
- Initial release
- LLM evaluation workbench for Phoenix applications
- Support for multiple LLM providers
- Prompt management and versioning
- Test suite creation and execution
- Run results tracking and analysis
- Web dashboard for visualization
- Standalone application option
