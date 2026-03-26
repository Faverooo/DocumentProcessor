require "test_helper"

class DocumentProcessing::Persistence::DbManagerTest < ActiveSupport::TestCase
  class FakeResolution
    attr_reader :employee

    def initialize(employee)
      @employee = employee
    end

    def matched?
      true
    end
  end

  class FakeRecipientResolver
    def initialize(employee)
      @employee = employee
    end

    def resolve(recipient_names:, raw_text:)
      FakeResolution.new(@employee)
    end
  end

  test "uploaded_documents_list returns minimal payload" do
    UploadedDocument.create!(original_filename: "a.pdf", storage_path: "/tmp/a", page_count: 1, checksum: "dbm-1", file_kind: "pdf")
    UploadedDocument.create!(original_filename: "b.csv", storage_path: "/tmp/b", page_count: 1, checksum: "dbm-2", file_kind: "csv")

    manager = DocumentProcessing::Persistence::DbManager.new
    list = manager.uploaded_documents_list

    filenames = list.map { |row| row[:original_filename] }

    assert_includes filenames, "a.pdf"
    assert_includes filenames, "b.csv"
    assert list.first.key?(:id)
    assert list.first.key?(:file_kind)
  end

  test "update_extracted_metadata merges metadata and sets confidence to 100 for updated keys" do
    # Clear any residual data from previous tests - delete in correct order for foreign keys
    ExtractedDocument.delete_all
    ProcessingItem.delete_all
    ProcessingRun.delete_all
    UploadedDocument.delete_all
    Employee.delete_all

    employee = Employee.create!(name: "Mario Rossi", email: "mario@test.it", employee_code: "EMP-DBM")
    uploaded = UploadedDocument.create!(original_filename: "u.pdf", storage_path: "/tmp/u", page_count: 1, checksum: "dbm-3", file_kind: "pdf")
    extracted = ExtractedDocument.create!(
      uploaded_document: uploaded,
      sequence: 1,
      page_start: 1,
      page_end: 1,
      metadata: { "company" => "Old" },
      confidence: { "company" => 20 }
    )

    manager = DocumentProcessing::Persistence::DbManager.new(
      recipient_resolver: FakeRecipientResolver.new(employee)
    )

    result = manager.update_extracted_metadata(
      extracted_document_id: extracted.id,
      metadata_updates: { "company" => "New Co", "recipient" => "Mario Rossi" }
    )

    assert_equal "New Co", result.metadata["company"]
    assert_equal 100, result.confidence["company"]
    assert_equal "Mario Rossi", result.recipient
    assert_equal employee.id, result.matched_employee_id
  ensure
    ExtractedDocument.delete_all
    ProcessingItem.delete_all
    ProcessingRun.delete_all
    UploadedDocument.delete_all
    Employee.delete_all
  end
end
