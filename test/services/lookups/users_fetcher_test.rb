require "test_helper"

class UsersFetcherTest < ActiveSupport::TestCase
  test "returns all employees when no company provided" do
    e1 = Employee.create!(name: "Mario", email: "m@x.it", employee_code: "E1")
    e2 = Employee.create!(name: "Luigi", email: "l@x.it", employee_code: "E2")

    result = DocumentProcessing::Lookups::UsersFetcher.new.call

    assert_includes result, e1
    assert_includes result, e2
  end

  test "filters employees by override_company and metadata company" do
    e1 = Employee.create!(name: "Mario", email: "m@x.it", employee_code: "E1")
    e2 = Employee.create!(name: "Luigi", email: "l@x.it", employee_code: "E2")

    ud = UploadedDocument.create!(original_filename: "a.pdf", storage_path: "/tmp/a", page_count: 1, checksum: "ch3", override_company: "ACME", file_kind: "pdf")
    ed = ExtractedDocument.create!(uploaded_document: ud, sequence: 1, page_start: 1, page_end: 1, matched_employee: e1, metadata: {})

    ud2 = UploadedDocument.create!(original_filename: "b.pdf", storage_path: "/tmp/b", page_count: 1, checksum: "ch4", file_kind: "pdf")
    ExtractedDocument.create!(uploaded_document: ud2, sequence: 1, page_start: 1, page_end: 1, matched_employee: e2, metadata: { "company" => "Beta" })

    res_acme = DocumentProcessing::Lookups::UsersFetcher.new.call(company: "ACME")
    assert_equal [e1], res_acme.to_a

    res_beta = DocumentProcessing::Lookups::UsersFetcher.new.call(company: "Beta")
    assert_equal [e2], res_beta.to_a
  end
end
