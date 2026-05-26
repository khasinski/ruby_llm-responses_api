# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-05-26

### Added

- Fire `on_tool_call` / `on_tool_result` (and the newer `before_tool_call` / `after_tool_result`) for server-side built-in tools: web search, file search, code interpreter, image generation, shell, apply patch, MCP, computer use, local shell (issue #1 by @myxoh)
- Configurable WebSocket `response_timeout` (default 60s); stalled streams now raise `ConnectionError` instead of hanging forever on `queue.pop`

### Fixed

- Stop sending the full message history alongside `previous_response_id` in chained conversations; this caused server-side chain state to grow quadratically and reach the context-window ceiling far earlier than the visible content suggested (issue #10 reported by @theclunkerjunker)
- Drop the rejected `OpenAI-Beta: responses.websocket=v1` header that prevented the live `wss://api.openai.com/v1/responses` endpoint from accepting connections
- Send `response.create` fields at the top level over WebSocket instead of nested under a `response` key, which made the live endpoint reject every request as `missing_required_parameter: model` (PR #8 by @lucas-domeij)
- Bind WebSocket `on(:message)` / `on(:close)` / `on(:error)` handlers via a local closure so they no longer reference ivars on the underlying client (which silently dropped every incoming frame and made `#call` hang) (PR #9 by @lucas-domeij)

### Changed

- `ruby_llm` dependency bumped to `>= 1.13` so the existing `thinking:` / `tool_prefs:` overrides match the upstream `Provider#complete` signature

## [0.5.4] - 2026-04-06

### Changed

- Raise `UnsupportedAttachmentError` for unknown attachment types instead of sending a confusing placeholder to the LLM (PR #7 by @molily)
- Remove unused `Media#format_content` method (dead code cleanup)

### Added

- Text file attachment support (`.txt`, `.csv`, `.html`, etc.) matching ruby_llm's standard OpenAI provider behavior (PR #7 by @molily)
- Consolidate attachment handling in `Media` module, removing duplicate logic from `Chat` (PR #7 by @molily)

## [0.5.3] - 2026-03-27

### Fixed

- Return string from `slug` instead of symbol to fix `Model.refresh!` sorting crash (PR #6 by @noelblaschke)

## [0.5.2] - 2026-03-18

### Fixed

- Fix streamed tool call accumulation: argument deltas no longer overwrite the tool name (PR #3 by @shllg)
- Fix gem packaging: correct file permissions from 600 to 644 (issue #2 by @myxoh)
- Move streaming unit tests to dedicated spec file

## [0.5.1] - 2026-03-03

### Added

- `tool_choice` support (`auto`, `required`, `none`, or specific function name)
- `parallel_tool_calls` support (`:many` / `:one`) via RubyLLM's `tool_prefs`

### Fixed

- Compatibility with RubyLLM v1.13.0 (`tool_prefs:` parameter in `complete` and `render_payload`)
- Handle new pre-normalized schema format from `Chat.with_schema`

## [0.5.0] - 2026-02-25

### Added

- **Batch API** for processing many requests asynchronously at 50% lower cost
  - `RubyLLM.batch(model:, provider:)` factory method
  - `Batch#add` to queue requests with auto-generated or custom IDs
  - `Batch#create!` to upload JSONL and create the batch in one call
  - `Batch#wait!` to poll until completion with progress callbacks
  - `Batch#results` returns a `Hash<custom_id, Message>` using the same parsing as `Chat`
  - `Batch#errors`, `Batch#cancel!`, and status helpers (`completed?`, `in_progress?`, `failed?`)
  - Resume from a previous session via `RubyLLM.batch(id: "batch_abc", provider: :openai_responses)`
  - `RubyLLM.batches` to list existing batches
  - `Batches` helper module with JSONL builder, URL helpers, and result parsing

## [0.4.1] - 2026-02-24

### Added

- `chat.with_params(transport: :websocket)` integration with standard `chat.ask` interface
- `WebSocket#call` for accepting pre-built payloads from the provider

### Fixed

- WebSocket responses now preserve token counts from `StreamAccumulator`

## [0.4.0] - 2026-02-24

### Added

- **WebSocket mode** for lower-latency agentic workflows with persistent `wss://` connections
  - `RubyLLM::ResponsesAPI::WebSocket` standalone class
  - Streamed responses via `create_response` with block
  - Automatic `previous_response_id` chaining across turns
  - `warmup` for server-side model weight caching (`generate: false`)
  - Thread-safe with one-at-a-time response constraint
  - Supports all existing helpers: `State`, `Compaction`, `Tools`
  - Soft dependency on `websocket-client-simple` (lazy require with clear error)

## [0.3.1] - 2026-02-18

### Fixed

- Compatibility with RubyLLM v1.12.0 (`thinking:` parameter in `render_payload`)

## [0.3.0] - 2026-02-11

### Added

- **Shell tool** support for executing commands in hosted or local terminal environments
  - Auto-provisioned containers (`container_auto`), reusable containers (`container_reference`), and local execution (`local`)
  - Container networking with domain allowlists and domain-scoped secrets
  - Configurable memory limits (`1g`, `4g`, `16g`, `64g`)
  - `BuiltInTools.shell` helper and `parse_shell_call_results` parser
- **Server-side compaction** for multi-hour agent runs without hitting context limits
  - `Compaction.compaction_params(compact_threshold:)` helper
  - Pass via `chat.with_params(context_management: [{ type: 'compaction', compact_threshold: 200_000 }])`
- **Containers API** for managing persistent execution environments
  - `create_container`, `retrieve_container`, `delete_container`
  - `list_container_files`, `retrieve_container_file`, `retrieve_container_file_content`
- **Apply Patch tool** for structured diff-based file editing
  - `BuiltInTools.apply_patch` helper and `parse_apply_patch_results` parser

## [0.2.0] - 2026-01-15

### Added

- Legacy ActiveRecord support
- CI compatibility fixes

## [0.1.0] - 2025-01-03

### Added

- Initial release of the RubyLLM Responses API provider
- Core chat completion support with Responses API format
- Streaming support with typed event handling
- Function calling (tool use) support
- Built-in tools support:
  - Web Search (`web_search_preview`)
  - Code Interpreter (`code_interpreter`)
  - File Search (`file_search`)
  - Image Generation (`image_generation`)
  - MCP (Model Context Protocol) (`mcp`)
  - Computer Use (`computer_use_preview`)
- Stateful conversation support via `previous_response_id` and `store`
- Background mode for long-running tasks
- Response polling and cancellation
- Message extension to support `response_id`
- Model capabilities for GPT-4o, GPT-4.1, and O-series models
- Media handling for images, PDFs, and audio
