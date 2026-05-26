# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::OpenAIResponses::Compaction do
  let(:compaction) { RubyLLM::Providers::OpenAIResponses::Compaction }

  describe '.compaction_params' do
    it 'returns context_management with default threshold' do
      params = compaction.compaction_params
      expect(params[:context_management]).to eq([{ type: 'compaction', compact_threshold: 200_000 }])
    end

    it 'accepts custom threshold' do
      params = compaction.compaction_params(compact_threshold: 100_000)
      expect(params[:context_management].first[:compact_threshold]).to eq(100_000)
    end
  end

  describe '.apply_compaction' do
    it 'applies compact_threshold shorthand to payload' do
      payload = { model: 'gpt-4o' }
      params = { compact_threshold: 150_000 }

      result = compaction.apply_compaction(payload, params)

      expect(result[:context_management]).to eq([{ type: 'compaction', compact_threshold: 150_000 }])
    end

    it 'applies explicit context_management to payload' do
      payload = { model: 'gpt-4o' }
      ctx = [{ type: 'compaction', compact_threshold: 250_000 }]
      params = { context_management: ctx }

      result = compaction.apply_compaction(payload, params)

      expect(result[:context_management]).to eq(ctx)
    end

    it 'does not modify payload when no compaction params' do
      payload = { model: 'gpt-4o' }
      result = compaction.apply_compaction(payload, {})

      expect(result).not_to have_key(:context_management)
    end

    it 'prefers compact_threshold over context_management' do
      payload = {}
      params = {
        compact_threshold: 100_000,
        context_management: [{ type: 'compaction', compact_threshold: 999_999 }]
      }

      result = compaction.apply_compaction(payload, params)
      expect(result[:context_management].first[:compact_threshold]).to eq(100_000)
    end
  end

  describe 'URL helpers' do
    it 'returns compact URL' do
      expect(compaction.compact_url).to eq('responses/compact')
    end

    it 'returns input token count URL' do
      expect(compaction.input_tokens_url).to eq('responses/input_tokens')
    end
  end

  describe 'namespace access' do
    it 'is accessible via RubyLLM::ResponsesAPI::Compaction' do
      expect(RubyLLM::ResponsesAPI::Compaction).to eq(compaction)
    end
  end
end
