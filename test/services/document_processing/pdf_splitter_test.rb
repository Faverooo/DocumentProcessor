require "test_helper"

class PdfSplitterTest < ActiveSupport::TestCase
  test "split maps ranges to mini pdf paths" do
    pdf = Struct.new(:pages).new([:p1, :p2])
    splitter = DocumentProcessing::PdfSplitter.new(pdf: pdf, ocr_service: Object.new, llm_service: Object.new)

    splitter.define_singleton_method(:identify_ranges) { [{ start: 0, end: 0 }, { start: 1, end: 1 }] }
    splitter.define_singleton_method(:create_mini_pdf) { |range:, index:| "/tmp/split_#{index}.pdf" }

    result = splitter.split

    assert_equal 2, result.size
    assert_equal "/tmp/split_0.pdf", result[0][:path]
    assert_equal({ start: 1, end: 1 }, result[1][:range])
  end

  test "breakpoints_to_ranges creates contiguous ranges" do
    pdf = Struct.new(:pages).new([:p1, :p2, :p3])
    splitter = DocumentProcessing::PdfSplitter.new(pdf: pdf, ocr_service: Object.new, llm_service: Object.new)

    ranges = splitter.send(:breakpoints_to_ranges, [0, 2])

    assert_equal [{ start: 0, end: 1 }, { start: 2, end: 2 }], ranges
  end
end
