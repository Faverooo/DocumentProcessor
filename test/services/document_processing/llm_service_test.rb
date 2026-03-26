require "test_helper"

class LlmServiceTest < ActiveSupport::TestCase
  class FakeBedrock
    attr_reader :last_args

    def initialize(text)
      @text = text
    end

    def converse(args)
      @last_args = args
      content_item = Struct.new(:text).new(@text)
      message = Struct.new(:content).new([content_item])
      output = Struct.new(:message).new(message)
      Struct.new(:output).new(output)
    end
  end

  test "extract_document_data parses json response" do
    client = FakeBedrock.new('{"recipients":[{"name":"Mario Rossi"}],"document":{"date":null}}')
    service = DocumentProcessing::LlmService.new(bedrock_client: client)

    result = service.extract_document_data("testo")

    assert_equal "Mario Rossi", result["recipients"][0]["name"]
    assert result.key?("document")
    assert_equal "amazon.nova-lite-v1:0", client.last_args[:model_id]
  end

  test "detect_split_breakpoints raises when no json is present" do
    client = FakeBedrock.new("risposta non valida")
    service = DocumentProcessing::LlmService.new(bedrock_client: client)

    assert_raises(RuntimeError) do
      service.detect_split_breakpoints("pagina 0")
    end
  end
end
