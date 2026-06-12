# frozen_string_literal: true

module RubyLLM
  module Providers
    # Namespace for Responses API extension helpers.
    #
    # On RubyLLM versions without the native Responses protocol this class is
    # also used as the legacy standalone provider.
    class OpenAIResponses < Provider
    end
  end
end
