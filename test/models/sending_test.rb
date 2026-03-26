require "test_helper"

class SendingTest < ActiveSupport::TestCase
  test "is valid with required attributes" do
    sending = Sending.new(
      extracted_document: extracted_document,
      recipient: recipient,
      sent_at: Time.current,
      subject: "Cedolino Marzo",
      body: "Testo del messaggio"
    )

    assert sending.valid?
  end

  test "requires extracted_document, recipient and sent_at" do
    sending = Sending.new

    assert_not sending.valid?
    assert_includes sending.errors[:extracted_document], "can't be blank"
    assert_includes sending.errors[:recipient], "can't be blank"
    assert_includes sending.errors[:sent_at], "can't be blank"
  end

  test "validates subject maximum length" do
    sending = Sending.new(
      extracted_document: extracted_document,
      recipient: recipient,
      sent_at: Time.current,
      subject: "a" * 256
    )

    assert_not sending.valid?
    assert_includes sending.errors[:subject], "is too long (maximum is 255 characters)"
  end

  test "validates body maximum length" do
    sending = Sending.new(
      extracted_document: extracted_document,
      recipient: recipient,
      sent_at: Time.current,
      body: "a" * 10_001
    )

    assert_not sending.valid?
    assert_includes sending.errors[:body], "is too long (maximum is 10000 characters)"
  end

  private

  def recipient
    @recipient ||= Employee.create!(name: "Giulia Bianchi", email: "giulia@azienda.it", employee_code: "EMP-SEND-1")
  end

  def extracted_document
    @extracted_document ||= ExtractedDocument.create!(
      uploaded_document: UploadedDocument.create!(
        original_filename: "source.pdf",
        storage_path: "/tmp/source.pdf",
        page_count: 1,
        checksum: "sum-send-1",
        file_kind: "pdf"
      ),
      sequence: 1,
      page_start: 1,
      page_end: 1
    )
  end
end
