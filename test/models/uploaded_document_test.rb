require "test_helper"

class UploadedDocumentTest < ActiveSupport::TestCase
  test "is valid with required attributes" do
    document = UploadedDocument.new(
      original_filename: "cedolino_marzo.pdf",
      storage_path: "/tmp/cedolino_marzo.pdf",
      page_count: 2,
      checksum: "sum-up-1",
      file_kind: "pdf"
    )

    assert document.valid?
  end

  test "is invalid without required fields" do
    document = UploadedDocument.new

    assert_not document.valid?
    assert_includes document.errors[:original_filename], "can't be blank"
    assert_includes document.errors[:storage_path], "can't be blank"
    assert_includes document.errors[:checksum], "can't be blank"
  end

  test "is invalid with negative page_count" do
    document = UploadedDocument.new(
      original_filename: "x.pdf",
      storage_path: "/tmp/x.pdf",
      page_count: -1,
      checksum: "sum-up-2"
    )

    assert_not document.valid?
    assert_includes document.errors[:page_count], "must be greater than or equal to 0"
  end

  test "enforces checksum uniqueness" do
    UploadedDocument.create!(
      original_filename: "a.pdf",
      storage_path: "/tmp/a.pdf",
      page_count: 1,
      checksum: "sum-up-3",
      file_kind: "pdf"
    )

    duplicate = UploadedDocument.new(
      original_filename: "b.pdf",
      storage_path: "/tmp/b.pdf",
      page_count: 1,
      checksum: "sum-up-3"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:checksum], "has already been taken"
  end

  test "rejects unknown file_kind values" do
    document = UploadedDocument.new(
      original_filename: "x.pdf",
      storage_path: "/tmp/x.pdf",
      page_count: 1,
      checksum: "sum-up-4",
      file_kind: "word"
    )

    assert_not document.valid?
    assert_includes document.errors[:file_kind], "is not included in the list"
  end

  test "destroys extracted_documents when deleted" do
    uploaded_document = UploadedDocument.create!(
      original_filename: "parent.pdf",
      storage_path: "/tmp/parent.pdf",
      page_count: 1,
      checksum: "sum-up-5",
      file_kind: "pdf"
    )

    ExtractedDocument.create!(
      uploaded_document: uploaded_document,
      sequence: 1,
      page_start: 1,
      page_end: 1
    )

    assert_difference("ExtractedDocument.count", -1) do
      uploaded_document.destroy
    end
  end
end
