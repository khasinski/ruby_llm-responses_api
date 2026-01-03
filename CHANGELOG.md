# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
