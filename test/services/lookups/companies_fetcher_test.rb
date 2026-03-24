require "test_helper"

class CompaniesFetcherTest < ActiveSupport::TestCase
  test "aggregates companies from uploaded documents and extracted metadata" do
    ud = UploadedDocument.create!(original_filename: "a.pdf", storage_path: "/tmp/a", page_count: 1, checksum: "ch1", override_company: "ACME")
    ud2 = UploadedDocument.create!(original_filename: "b.pdf", storage_path: "/tmp/b", page_count: 1, checksum: "ch2")

    ExtractedDocument.create!(uploaded_document: ud2, sequence: 1, page_start: 1, page_end: 1, metadata: { "company" => "Beta" })

    result = Lookups::CompaniesFetcher.new.call

    assert_equal ["ACME", "Beta"], result
  end
end
