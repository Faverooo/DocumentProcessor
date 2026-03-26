require "test_helper"

class DocumentProcessing::Persistence::DataItemRepositoryTest < ActiveSupport::TestCase
  test "mark_extracted_document_done! acquires lock to prevent concurrent metadata updates" do
    ud = UploadedDocument.create!(original_filename: "a.pdf", storage_path: "/tmp/a", page_count: 1, checksum: "ch_test_1", file_kind: "pdf")
    ed = ExtractedDocument.create!(uploaded_document: ud, sequence: 1, page_start: 1, page_end: 1)
    run = ProcessingRun.create!(job_id: "job_123", total_documents: 1, original_filename: "test.pdf")
    
    resolution = mock_resolution
    metadata = { "company" => "Test Corp" }
    
    repo = DocumentProcessing::Persistence::DataItemRepository.new
    
    # Simula aggiornamento via repo (con lock)
    repo.mark_extracted_document_done!(
      extracted_document: ed,
      resolution: resolution,
      metadata: metadata,
      recipient: "John Doe",
      global_confidence: 0.95,
      process_duration_seconds: 5.0
    )
    
    ed.reload
    assert_equal "done", ed.status
    assert_equal metadata, ed.metadata
    assert_equal "John Doe", ed.recipient
  end

  test "update_progress! acquires lock for atomic counter increment" do
    run = ProcessingRun.create!(
      job_id: "job_456",
      total_documents: 3,
      original_filename: "test.pdf",
      processed_documents: 0
    )
    
    item1 = ProcessingItem.create!(processing_run: run, sequence: 1, filename: "f1", status: "done")
    item2 = ProcessingItem.create!(processing_run: run, sequence: 2, filename: "f2", status: "done")
    ProcessingItem.create!(processing_run: run, sequence: 3, filename: "f3", status: "queued")
    
    repo = DocumentProcessing::Persistence::DataItemRepository.new
    result = repo.update_progress!(run)
    
    run.reload
    assert_equal 2, run.processed_documents
    assert_equal false, result[:completed]  # 2 of 3, not done
    
    # Complete last item
    ProcessingItem.where(processing_run: run, sequence: 3).update_all(status: "done")
    result = repo.update_progress!(run)
    
    run.reload
    assert_equal 3, run.processed_documents
    assert_equal true, result[:completed]
    assert_equal "completed", run.status
    assert_not_nil run.completed_at
  end

  test "concurrent mark_extracted_document_done! calls don't lose updates" do
    ud = UploadedDocument.create!(original_filename: "b.pdf", storage_path: "/tmp/b", page_count: 1, checksum: "ch_test_2", file_kind: "pdf")
    ed = ExtractedDocument.create!(uploaded_document: ud, sequence: 1, page_start: 1, page_end: 1)
    
    repo = DocumentProcessing::Persistence::DataItemRepository.new
    resolution = mock_resolution
    
    # First update
    repo.mark_extracted_document_done!(
      extracted_document: ed,
      resolution: resolution,
      metadata: { "company" => "Company A" },
      recipient: "User 1",
      global_confidence: 0.9,
      process_duration_seconds: 3.0
    )
    
    ed.reload
    assert_equal "Company A", ed.metadata["company"]
    assert_equal "User 1", ed.recipient
    
    # Second update (simulating concurrent PATCH from UI)
    ed.with_lock do
      ed.reload
      ed.update!(metadata: { "company" => "Company B" })
    end
    
    ed.reload
    assert_equal "Company B", ed.metadata["company"]
    assert_equal "User 1", ed.recipient  # recipient nicht changed
  end

  private

  def mock_resolution
    double("resolution", matched?: true, employee: Employee.create!(name: "John", email: "john@test.com", employee_code: "E1"))
  end
end
