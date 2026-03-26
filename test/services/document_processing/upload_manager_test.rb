require "test_helper"

class UploadManagerTest < ActiveSupport::TestCase
  class FakeUpload
    attr_reader :original_filename, :content_type, :tempfile

    def initialize(original_filename:, content_type:, content:)
      @original_filename = original_filename
      @content_type = content_type
      @tempfile = Tempfile.new(["upload", File.extname(original_filename)])
      @tempfile.binmode
      @tempfile.write(content)
      @tempfile.rewind
    end

    def read(*args)
      @tempfile.read(*args)
    end

    def rewind
      @tempfile.rewind
    end

    def size
      @tempfile.size
    end
  end

  test "detect_upload_kind recognizes pdf csv and image" do
    manager = DocumentProcessing::UploadManager.new

    assert_equal :pdf, manager.detect_upload_kind(FakeUpload.new(original_filename: "a.pdf", content_type: "application/pdf", content: "%PDF-1.4"))
    assert_equal :csv, manager.detect_upload_kind(FakeUpload.new(original_filename: "a.csv", content_type: "text/csv", content: "x"))
    assert_equal :image, manager.detect_upload_kind(FakeUpload.new(original_filename: "a.png", content_type: "image/png", content: "x"))
  end

  test "persist_temp_pdf rejects invalid pdf signature" do
    manager = DocumentProcessing::UploadManager.new
    fake = FakeUpload.new(original_filename: "bad.pdf", content_type: "application/pdf", content: "NOTPDF")

    assert_raises(DocumentProcessing::UploadManager::ValidationError) do
      manager.persist_temp_pdf(fake)
    end
  end

  test "compute_checksum is stable" do
    manager = DocumentProcessing::UploadManager.new
    fake = FakeUpload.new(original_filename: "ok.pdf", content_type: "application/pdf", content: "%PDF-abc")

    c1 = manager.compute_checksum(fake)
    c2 = manager.compute_checksum(fake)

    assert_equal c1, c2
  end
end
