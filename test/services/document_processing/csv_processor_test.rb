require "test_helper"

class CsvProcessorTest < ActiveSupport::TestCase
  test "parse returns rows as hashes" do
    temp = Tempfile.new(["rows", ".csv"])
    temp.write("recipient,amount\nMario Rossi,100\nGiulia Bianchi,200\n")
    temp.rewind

    rows = DocumentProcessing::CsvProcessor.new(data_extractor: nil, recipient_resolver: nil).parse(temp.path)

    assert_equal 2, rows.size
    assert_equal "Mario Rossi", rows[0]["recipient"]
    assert_equal "200", rows[1]["amount"]
  ensure
    temp.close!
  end
end
