# frozen_string_literal: true

module RubyLLM
  module Providers
    class OpenAIResponses
      # Media handling methods for the OpenAI Responses API.
      # Handles images, audio, PDFs, and other file types.
      module Media
        module_function

        def format_content(content)
          return content if content.is_a?(RubyLLM::Content::Raw)
          return content unless content.is_a?(RubyLLM::Content)

          parts = []
          parts << format_text(content.text) if content.text && !content.text.empty?

          content.attachments.each do |attachment|
            parts << format_attachment(attachment)
          end

          # Return simple string for text-only content
          return content.text if parts.length == 1 && parts.first[:type] == 'input_text'

          parts
        end

        def format_text(text)
          { type: 'input_text', text: text }
        end

        def format_attachment(attachment)
          case attachment.type
          when :image
            format_image(attachment)
          when :pdf
            format_pdf(attachment)
          when :audio
            format_audio(attachment)
          else
            format_unknown(attachment)
          end
        end

        def format_image(image)
          if image.url?
            {
              type: 'input_image',
              image_url: image.source
            }
          else
            {
              type: 'input_image',
              image_url: image.for_llm
            }
          end
        end

        def format_pdf(pdf)
          {
            type: 'input_file',
            filename: extract_filename(pdf.source),
            file_data: pdf.for_llm
          }
        end

        def format_audio(audio)
          {
            type: 'input_audio',
            data: audio.for_llm,
            format: detect_audio_format(audio.source)
          }
        end

        def format_unknown(attachment)
          {
            type: 'input_text',
            text: "[Attachment: #{attachment.type}]"
          }
        end

        def extract_filename(source)
          return 'file' unless source

          if source.respond_to?(:path)
            File.basename(source.path)
          else
            File.basename(source.to_s)
          end
        end

        def detect_audio_format(source)
          return 'mp3' unless source

          ext = if source.respond_to?(:path)
                  File.extname(source.path)
                else
                  File.extname(source.to_s)
                end

          case ext.downcase
          when '.mp3' then 'mp3'
          when '.wav' then 'wav'
          when '.webm' then 'webm'
          when '.ogg' then 'ogg'
          when '.flac' then 'flac'
          when '.m4a' then 'm4a'
          else 'mp3'
          end
        end
      end
    end
  end
end
