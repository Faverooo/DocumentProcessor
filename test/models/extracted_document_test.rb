require "test_helper"

class ExtractedDocumentTest < ActiveSupport::TestCase
  test "is valid with required attributes" do
    document = ExtractedDocument.new(
      uploaded_document: build_uploaded_document("sum-ex-1"),
      sequence: 1,
      page_start: 1,
      page_end: 2,
      status: "queued"
    )

    assert document.valid?
  end

  test "is invalid when page_end is before page_start" do
    document = ExtractedDocument.new(
      uploaded_document: build_uploaded_document("sum-ex-2"),
      sequence: 1,
      page_start: 3,
      page_end: 2
    )

    assert_not document.valid?
    assert_includes document.errors[:page_end], "deve essere maggiore o uguale a page_start"
  end

  test "is invalid without sequence" do
    document = ExtractedDocument.new(
      uploaded_document: build_uploaded_document("sum-ex-3"),
      page_start: 1,
      page_end: 1
    )

    assert_not document.valid?
    assert_includes document.errors[:sequence], "can't be blank"
  end

  test "rejects unknown status values" do
    document = ExtractedDocument.new(
      uploaded_document: build_uploaded_document("sum-ex-4"),
      sequence: 1,
      page_start: 1,
      page_end: 1,
      status: "unknown"
    )

    assert_not document.valid?
    assert_includes document.errors[:status], "is not included in the list"
  end

  private

  def build_uploaded_document(checksum)
    UploadedDocument.create!(
      original_filename: "sample.pdf",
      storage_path: "/tmp/sample.pdf",
      page_count: 1,
      checksum: checksum,
      file_kind: "pdf"
    )
  end
end
