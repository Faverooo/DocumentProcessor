require "test_helper"

class DocumentsFlowTest < ActionDispatch::IntegrationTest
  test "split delegates to initialize processing command" do
    command = FakeCommand.new(
      result: {
        message: "Pipeline avviata: split in corso, processamento documenti automatico",
        job_id: "job-123",
        uploaded_document_id: 42
      }
    )

    DocumentProcessing::Commands::InitializeProcessing.stub(:new, command) do
      post split_documents_path, params: { pdf: uploaded_pdf_file }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "queued", body["status"]
    assert_equal "job-123", body["job_id"]
    assert_equal 42, body["uploaded_document_id"]
  end

  test "split returns bad request when command raises validation error" do
    command = FakeCommand.new(error: DocumentProcessing::UploadManager::ValidationError.new("Formato non valido: carica un PDF"))

    DocumentProcessing::Commands::InitializeProcessing.stub(:new, command) do
      post split_documents_path, params: { pdf: uploaded_pdf_file }
    end

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "error", body["status"]
    assert_equal "Formato non valido: carica un PDF", body["message"]
  end

  test "reassign_range delegates to command and returns queued response" do
    uploaded_document = UploadedDocument.create!(
      original_filename: "source.pdf",
      storage_path: "/tmp/source.pdf",
      page_count: 10
    )
    extracted_document = uploaded_document.extracted_documents.create!(
      sequence: 1,
      page_start: 1,
      page_end: 2,
      status: "queued"
    )

    command = FakeCommand.new(
      result: {
        message: "Riassegnazione completata, analisi rilanciata",
        extracted_document_id: extracted_document.id,
        page_start: 3,
        page_end: 5
      }
    )

    DocumentProcessing::Commands::ReassignExtractedRange.stub(:new, command) do
      patch reassign_extracted_document_range_path(id: extracted_document.id), params: { page_start: 3, page_end: 5 }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "queued", body["status"]
    assert_equal extracted_document.id, body["extracted_document_id"]
    assert_equal 3, body["page_start"]
    assert_equal 5, body["page_end"]
  end

  test "reassign_range returns not found when command raises record not found" do
    command = FakeCommand.new(error: ActiveRecord::RecordNotFound.new("not found"))

    DocumentProcessing::Commands::ReassignExtractedRange.stub(:new, command) do
      patch reassign_extracted_document_range_path(id: 999_999), params: { page_start: 1, page_end: 2 }
    end

    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "error", body["status"]
  end

  test "extracted_pdf returns bad request when source pdf does not exist" do
    uploaded_document = UploadedDocument.create!(
      original_filename: "source.pdf",
      storage_path: "/tmp/not_existing_source.pdf",
      page_count: 3
    )
    extracted_document = uploaded_document.extracted_documents.create!(
      sequence: 1,
      page_start: 1,
      page_end: 1,
      status: "queued"
    )

    get extracted_pdf_document_path(id: extracted_document.id)

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "error", body["status"]
    assert_equal "PDF sorgente non disponibile", body["message"]
  end

  private

  def uploaded_pdf_file
    temp = Tempfile.new(["upload", ".pdf"])
    temp.binmode
    temp.write("%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF")
    temp.rewind
    Rack::Test::UploadedFile.new(temp.path, "application/pdf", original_filename: "document.pdf")
  end

  class FakeCommand
    def initialize(result: nil, error: nil)
      @result = result
      @error = error
    end

    def call(**)
      raise @error if @error

      @result
    end
  end
end