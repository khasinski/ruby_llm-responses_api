# frozen_string_literal: true

# Historic recordings use the 0.x wire format. Match equivalent requests while
# keeping the original recordings intact; protocol_spec asserts the 2.x payloads.
module LegacyRequestMatcher
  module_function

  def body(request)
    data = JSON.parse(request.body)
    return data unless request.uri.end_with?('/responses')

    data.delete('store') if data['store'] == true
    data.delete('include') if data['include'] == ['reasoning.encrypted_content']
    data['input'] = Array(data['input']).map { |item| input_item(item) }
    if data['previous_response_id']
      anchor = data['input'].rindex { |item| item['role'] == 'assistant' || item['type'] == 'function_call' }
      data['input'] = data['input'][(anchor + 1)..] if anchor
    end
    data
  rescue JSON::ParserError
    request.body
  end

  def input_item(item)
    item = item.dup
    item.delete('type') if item['type'] == 'message'
    parts = item['content']
    if parts.is_a?(Array) && parts.size == 1 && parts.first['type'] == 'input_text'
      item['content'] = parts.first['text']
    end
    item
  end
end

VCR.configure do |config|
  config.register_request_matcher(:legacy_responses_body) do |left, right|
    a = LegacyRequestMatcher.body(left)
    b = LegacyRequestMatcher.body(right)
    a == b
  end
end
