require "test_helper"

class DocumentProcessing::Persistence::SplitRunRepositoryTest < ActiveSupport::TestCase
  test "create_split_artifacts creates processing items and extracted documents" do
    uploaded = UploadedDocument.create!(
      original_filename: "source.pdf",
      storage_path: "/tmp/source.pdf",
      page_count: 2,
      checksum: "split-repo-1",
      file_kind: "pdf"
    )
    run = ProcessingRun.create!(job_id: "split-job-1", uploaded_document: uploaded)

    repo = DocumentProcessing::Persistence::SplitRunRepository.new
    artifacts = repo.create_split_artifacts!(
      run: run,
      split_results: [
        { range: { start: 0, end: 0 }, path: "/tmp/mini_1.pdf" },
        { range: { start: 1, end: 1 }, path: "/tmp/mini_2.pdf" }
      ]
    )

    assert_equal 2, artifacts.size
    assert_equal 2, run.processing_items.count
    assert_equal 2, uploaded.extracted_documents.count
  end

  test "mark_post_split_state marks completed when split_count is zero" do
    run = ProcessingRun.create!(job_id: "split-job-2", status: "queued")
    repo = DocumentProcessing::Persistence::SplitRunRepository.new

    repo.mark_post_split_state!(run: run, split_count: 0)
    run.reload

    assert_equal "completed", run.status
    assert_equal 0, run.total_documents
    assert_equal 0, run.processed_documents
    assert_not_nil run.completed_at
  end
end
