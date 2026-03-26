require "test_helper"

class ExtractedDocumentPresenterTest < ActiveSupport::TestCase
  class FakeUrlHelpers
    def extracted_pdf_document_path(id:)
      "/documents/extracted/#{id}/pdf"
    end
  end

  test "as_json includes expected fields and formatted employee" do
    employee = Employee.create!(name: "Mario", email: "mario@test.it", employee_code: "EMP-PRES")
    uploaded = UploadedDocument.create!(original_filename: "x.pdf", storage_path: "/tmp/x", page_count: 1, checksum: "pres-1", file_kind: "pdf")
    doc = ExtractedDocument.create!(
      uploaded_document: uploaded,
      matched_employee: employee,
      sequence: 1,
      page_start: 1,
      page_end: 1,
      status: "done",
      metadata: { "type" => "cedolino" },
      recipient: "Mario"
    )

    payload = DocumentProcessing::Presenters::ExtractedDocumentPresenter.new(doc, url_helpers: FakeUrlHelpers.new).as_json

    assert_equal doc.id, payload[:id]
    assert_equal "done", payload[:status]
    assert_equal "Mario", payload[:recipient]
    assert_equal employee.email, payload[:matched_employee][:email]
    assert_equal "/documents/extracted/#{doc.id}/pdf", payload[:pdf_download_url]
  end
end
