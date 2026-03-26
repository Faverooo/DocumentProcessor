require "test_helper"

class DocumentProcessing::Sendings::CreateSendingTest < ActiveSupport::TestCase
  test "creates sending successfully with subject" do
    recipient = Employee.create!(name: "Mario", email: "mario@x.it", employee_code: "M1")
    ud = UploadedDocument.create!(original_filename: "a.pdf", storage_path: "/tmp/a", page_count: 1, checksum: "ch20", file_kind: "pdf")
    ed = ExtractedDocument.create!(uploaded_document: ud, sequence: 1, page_start: 1, page_end: 1)

    result = DocumentProcessing::Sendings::CreateSending.new(
      extracted_document_id: ed.id,
      recipient_id: recipient.id,
      sent_at: Time.current,
      subject: "Test Subject"
    ).call

    assert result.success?
    assert_equal "Test Subject", result.result[:sending].subject
  end

  test "creates sending successfully with custom body" do
    recipient = Employee.create!(name: "Mario", email: "mario-body@x.it", employee_code: "M1B")
    ud = UploadedDocument.create!(original_filename: "ab.pdf", storage_path: "/tmp/ab", page_count: 1, checksum: "ch20b", file_kind: "pdf")
    ed = ExtractedDocument.create!(uploaded_document: ud, sequence: 1, page_start: 1, page_end: 1)

    result = DocumentProcessing::Sendings::CreateSending.new(
      extracted_document_id: ed.id,
      recipient_id: recipient.id,
      sent_at: Time.current,
      subject: "Test Subject",
      body: "Testo custom inviato manualmente"
    ).call

    assert result.success?
    assert_equal "Testo custom inviato manualmente", result.result[:sending].body
  end

  test "creates sending and inherits subject from template" do
    recipient = Employee.create!(name: "Mario", email: "mario@x.it", employee_code: "M2")
    ud = UploadedDocument.create!(original_filename: "b.pdf", storage_path: "/tmp/b", page_count: 1, checksum: "ch21", file_kind: "pdf")
    ed = ExtractedDocument.create!(uploaded_document: ud, sequence: 1, page_start: 1, page_end: 1)
    template = Template.create!(subject: "Template Subject", body: "Template body")

    result = DocumentProcessing::Sendings::CreateSending.new(
      extracted_document_id: ed.id,
      recipient_id: recipient.id,
      sent_at: Time.current,
      template_id: template.id
    ).call

    assert result.success?
    assert_equal "Template Subject", result.result[:sending].subject
    assert_equal "Template body", result.result[:sending].body
  end

  test "fails with missing extracted_document_id" do
    result = DocumentProcessing::Sendings::CreateSending.new(
      extracted_document_id: nil,
      recipient_id: 1,
      sent_at: Time.current
    ).call

    assert !result.success?
    assert result.result[:error].include?("obbligatori")
  end

  test "fails with missing recipient_id" do
    result = DocumentProcessing::Sendings::CreateSending.new(
      extracted_document_id: 1,
      recipient_id: nil,
      sent_at: Time.current
    ).call

    assert !result.success?
    assert result.result[:error].include?("obbligatori")
  end

  test "prefers explicit subject over template subject" do
    recipient = Employee.create!(name: "Luigi", email: "luigi@x.it", employee_code: "L1")
    ud = UploadedDocument.create!(original_filename: "c.pdf", storage_path: "/tmp/c", page_count: 1, checksum: "ch22", file_kind: "pdf")
    ed = ExtractedDocument.create!(uploaded_document: ud, sequence: 1, page_start: 1, page_end: 1)
    template = Template.create!(subject: "Template Subject", body: "Body")

    result = DocumentProcessing::Sendings::CreateSending.new(
      extracted_document_id: ed.id,
      recipient_id: recipient.id,
      sent_at: Time.current,
      subject: "Explicit Subject",
      template_id: template.id
    ).call

    assert result.success?
    assert_equal "Explicit Subject", result.result[:sending].subject
  end
end
