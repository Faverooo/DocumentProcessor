require "test_helper"
require "digest"

class InitializeProcessingTest < ActiveSupport::TestCase
  class FakeUploadManager
    def initialize(path: "/tmp/source.pdf", checksum: "init-checksum")
      @path = path
      @checksum = checksum
    end

    def persist_source_pdf(_file)
      @path
    end

    def compute_checksum(_file)
      @checksum
    end
  end

  class FakePdfLoader
    def self.load(_path)
      Struct.new(:pages).new([:a, :b, :c])
    end
  end

  class FakePdfSplitJob
    cattr_accessor :calls, default: []

    def self.perform_later(*args)
      self.calls << args
    end
  end

  class FakeFile
    attr_reader :original_filename

    def initialize(filename = "source.pdf", content = "fake-pdf-content")
      @original_filename = filename
      @content = content
      @position = 0
    end

    def tempfile
      self
    end

    def read
      @content
    end

    def rewind
      @position = 0
    end
  end

  test "creates uploaded document, run and enqueues split" do
    file = FakeFile.new("source.pdf")

    command = DocumentProcessing::Commands::InitializeProcessing.new(
      upload_manager: FakeUploadManager.new,
      pdf_split_job_class: FakePdfSplitJob,
      pdf_loader: FakePdfLoader,
      file_storage: DocumentProcessing::Persistence::FileStorage.new
    )

    result = command.call(file: file, category: "cedolino")

    uploaded = UploadedDocument.find(result[:uploaded_document_id])

    assert_equal "pdf", uploaded.file_kind
    assert_equal "cedolino", uploaded.category
    assert_not_nil ProcessingRun.find_by(job_id: result[:job_id])
    assert_equal 1, FakePdfSplitJob.calls.size
  ensure
    FakePdfSplitJob.calls = []
  end

  test "returns existing uploaded document when checksum already exists" do
    # Clear any residual data from previous tests - delete in correct order for foreign keys
    ExtractedDocument.delete_all
    ProcessingItem.delete_all
    ProcessingRun.delete_all
    UploadedDocument.delete_all

    # Create a file with specific content so we can compute the same checksum
    file_content = "fake-pdf-content"
    expected_checksum = Digest::SHA256.hexdigest(file_content)

    existing = UploadedDocument.create!(
      original_filename: "old.pdf",
      storage_path: "/tmp/old.pdf",
      page_count: 1,
      checksum: expected_checksum,
      file_kind: "pdf"
    )

    file = FakeFile.new("new.pdf", file_content)
    command = DocumentProcessing::Commands::InitializeProcessing.new(
      upload_manager: FakeUploadManager.new(checksum: expected_checksum),
      pdf_split_job_class: FakePdfSplitJob,
      pdf_loader: FakePdfLoader,
      file_storage: DocumentProcessing::Persistence::FileStorage.new
    )

    result = command.call(file: file)

    assert_nil result[:job_id]
    assert_equal existing.id, result[:uploaded_document_id]
    assert_equal "Documento già caricato; riutilizzo documento esistente", result[:message]
  ensure
    FakePdfSplitJob.calls = []
    ExtractedDocument.delete_all
    ProcessingItem.delete_all
    ProcessingRun.delete_all
    UploadedDocument.delete_all
  end
end
