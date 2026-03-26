require "test_helper"

class EnqueueSingleDataExtractionTest < ActiveSupport::TestCase
  class FakeUploadManager
    attr_accessor :should_fail

    def initialize(should_fail: false)
      @should_fail = should_fail
    end

    def persist_temp_pdf(_file)
      raise "File storage error" if should_fail
      "/tmp/single.pdf"
    end
  end

  class FakeDataExtractionJob
    cattr_accessor :calls, default: []

    def self.perform_later(*args)
      self.calls << args
    end
  end

  setup do
    # Clear any residual data (delete_all in correct FK order)
    ProcessingItem.delete_all
    ProcessingRun.delete_all
    FakeDataExtractionJob.calls = []
  end

  # Happy path test
  test "creates processing run and enqueues extraction job" do
    command = DocumentProcessing::Commands::EnqueueSingleDataExtraction.new(
      upload_manager: FakeUploadManager.new,
      data_extraction_job_class: FakeDataExtractionJob
    )

    file = Struct.new(:original_filename).new("single.pdf")
    result = command.call(file: file)

    run = ProcessingRun.where(job_id: result[:job_id]).first
    assert_not_nil run, "Processing run with job_id should exist"
    assert_equal "processing", run.status
    assert_equal 1, run.processing_items.count
    assert_equal 1, FakeDataExtractionJob.calls.size
  end

  # Outbound interaction test
  test "outbound: passes temp file path and job metadata to extraction job" do
    command = DocumentProcessing::Commands::EnqueueSingleDataExtraction.new(
      upload_manager: FakeUploadManager.new,
      data_extraction_job_class: FakeDataExtractionJob
    )

    file = Struct.new(:original_filename).new("invoice.pdf")
    result = command.call(file: file)

    job_args = FakeDataExtractionJob.calls.first
    temp_path = job_args[0]
    job_metadata = job_args[1]

    assert_equal "/tmp/single.pdf", temp_path
    assert_equal result[:job_id], job_metadata[:job_id]
    assert_not_nil job_metadata[:processing_item_id]
  end

  # State validation test
  test "processing item created with queued status" do
    command = DocumentProcessing::Commands::EnqueueSingleDataExtraction.new(
      upload_manager: FakeUploadManager.new,
      data_extraction_job_class: FakeDataExtractionJob
    )

    file = Struct.new(:original_filename).new("pending.pdf")
    result = command.call(file: file)

    run = ProcessingRun.where(job_id: result[:job_id]).first
    item = run.processing_items.first
    assert_not_nil item
    assert_equal "queued", item.status
  end

  # Error case test
  test "error: handles file persistence error" do
    initial_count = ProcessingRun.count

    command = DocumentProcessing::Commands::EnqueueSingleDataExtraction.new(
      upload_manager: FakeUploadManager.new(should_fail: true),
      data_extraction_job_class: FakeDataExtractionJob
    )

    file = Struct.new(:original_filename).new("failed.pdf")

    assert_raises RuntimeError do
      command.call(file: file)
    end

    # Verify transaction rolled back
    assert_equal initial_count, ProcessingRun.count
  end

  # Edge case test
  test "edge case: generates unique job_id for each call" do
    initial_count = ProcessingRun.count

    command = DocumentProcessing::Commands::EnqueueSingleDataExtraction.new(
      upload_manager: FakeUploadManager.new,
      data_extraction_job_class: FakeDataExtractionJob
    )

    file1 = Struct.new(:original_filename).new("doc1.pdf")
    file2 = Struct.new(:original_filename).new("doc2.pdf")

    result1 = command.call(file: file1)
    result2 = command.call(file: file2)

    assert_not_equal result1[:job_id], result2[:job_id]
    assert_equal initial_count + 2, ProcessingRun.count
  end

  # Business logic test
  test "preserves original filename in processing run" do
    command = DocumentProcessing::Commands::EnqueueSingleDataExtraction.new(
      upload_manager: FakeUploadManager.new,
      data_extraction_job_class: FakeDataExtractionJob
    )

    file = Struct.new(:original_filename).new("special-report_2025.pdf")
    result = command.call(file: file)

    run = ProcessingRun.where(job_id: result[:job_id]).first
    assert_equal "special-report_2025.pdf", run.original_filename
  end
end
