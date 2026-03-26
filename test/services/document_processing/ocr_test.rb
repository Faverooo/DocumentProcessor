require "test_helper"

class OcrTest < ActiveSupport::TestCase
  test "page_texts_with_layout maps each page" do
    ocr = DocumentProcessing::Ocr.new(textract_client: Object.new)
    pdf = Struct.new(:pages).new([:a, :b])

    ocr.define_singleton_method(:layout_text) { |page| "txt-#{page}" }

    assert_equal ["txt-a", "txt-b"], ocr.page_texts_with_layout(pdf)
  end

  test "full_ocr combines line items into text and lines" do
    ocr = DocumentProcessing::Ocr.new(textract_client: Object.new)
    fake_pdf = Struct.new(:pages).new([:page1])

    ocr.define_singleton_method(:extract_line_items) do |_page|
      [{ text: "Mario Rossi", confidence: 91.0 }, { text: "ACME", confidence: 88.0 }]
    end

    original_load = CombinePDF.method(:load)
    CombinePDF.define_singleton_method(:load) { |_path| fake_pdf }

    result = ocr.full_ocr("/tmp/source.pdf")

    assert_equal "Mario Rossi\nACME", result[:text]
    assert_equal 2, result[:lines].size
  ensure
    CombinePDF.define_singleton_method(:load, original_load)
  end
end
