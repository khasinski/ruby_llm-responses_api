# frozen_string_literal: true

module RubyLLM
  module Providers
    # OpenAI Responses API provider for RubyLLM.
    # Implements the new Responses API which provides built-in tools,
    # stateful conversations, background mode, and MCP support.
    #
    # This base file defines the class structure before modules are loaded
    # to avoid "superclass mismatch" errors.
    class OpenAIResponses < Provider
    end
  end
end
