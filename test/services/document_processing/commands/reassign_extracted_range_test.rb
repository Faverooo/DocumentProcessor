require "test_helper"

class ReassignExtractedRangeTest < ActiveSupport::TestCase
  class FakePageRangePdf
    def initialize(source_pdf_path:)
      @source_pdf_path = source_pdf_path
    end

    def build_temp_pdf(page_start:, page_end:)
      "/tmp/reassigned_#{page_start}_#{page_end}.pdf"
    end
  end

  class FakeDataExtractionJob
    cattr_accessor :calls, default: []

    def self.perform_later(*args)
      self.calls << args
    end
  end

  class FakeFileStorage
    def exist?(_path)
      true
    end
  end

  test "reassigns range and enqueues extraction" do
    uploaded = UploadedDocument.create!(
      original_filename: "source.pdf",
      storage_path: "/tmp/source.pdf",
      page_count: 5,
      checksum: "reassign-1",
      file_kind: "pdf"
    )

    extracted = ExtractedDocument.create!(
      uploaded_document: uploaded,
      sequence: 1,
      page_start: 1,
      page_end: 2,
      status: "done",
      metadata: { "a" => 1 },
      recipient: "Mario",
      confidence: { "recipient" => 0.9 }
    )

    command = DocumentProcessing::Commands::ReassignExtractedRange.new(
      page_range_pdf_service_class: FakePageRangePdf,
      data_extraction_job_class: FakeDataExtractionJob,
      file_storage: FakeFileStorage.new
    )

    result = command.call(extracted_document_id: extracted.id, page_start: 2, page_end: 3)
    extracted.reload

    assert_equal extracted.id, result[:extracted_document_id]
    assert_equal "queued", extracted.status
    assert_equal({}, extracted.metadata)
    assert_nil extracted.recipient
    assert_equal 1, FakeDataExtractionJob.calls.size
  ensure
    FakeDataExtractionJob.calls = []
  end

  test "raises validation error for invalid range" do
    uploaded = UploadedDocument.create!(
      original_filename: "source.pdf",
      storage_path: "/tmp/source.pdf",
      page_count: 2,
      checksum: "reassign-2",
      file_kind: "pdf"
    )
    extracted = ExtractedDocument.create!(
      uploaded_document: uploaded,
      sequence: 1,
      page_start: 1,
      page_end: 1,
      status: "done"
    )

    command = DocumentProcessing::Commands::ReassignExtractedRange.new(
      page_range_pdf_service_class: FakePageRangePdf,
      data_extraction_job_class: FakeDataExtractionJob,
      file_storage: FakeFileStorage.new
    )

    assert_raises(DocumentProcessing::Commands::ReassignExtractedRange::ValidationError) do
      command.call(extracted_document_id: extracted.id, page_start: 0, page_end: 0)
    end
  end
end
