require "test_helper"

class PageRangePdfTest < ActiveSupport::TestCase
  test "build_temp_pdf creates pdf for valid range" do
    source = Rails.root.join("test.pdf").to_s
    skip "test.pdf non presente in root" unless File.exist?(source)

    service = DocumentProcessing::PageRangePdf.new(source_pdf_path: source)
    output = service.build_temp_pdf(page_start: 1, page_end: 1)

    assert File.exist?(output)
  ensure
    File.delete(output) if output && File.exist?(output)
  end

  test "build_temp_pdf raises on invalid range" do
    source = Rails.root.join("test.pdf").to_s
    skip "test.pdf non presente in root" unless File.exist?(source)

    service = DocumentProcessing::PageRangePdf.new(source_pdf_path: source)

    assert_raises(ArgumentError) do
      service.build_temp_pdf(page_start: 2, page_end: 1)
    end
  end
end
