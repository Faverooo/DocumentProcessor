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

  test "process_file delegates to initialize file processing command" do
    command = FakeCommand.new(
      result: {
        status: "queued",
        message: "Pipeline avviata: analisi file in coda",
        job_id: "job-file-123",
        uploaded_document_id: 77
      }
    )

    DocumentProcessing::Commands::InitializeFileProcessing.stub(:new, command) do
      post process_file_documents_path, params: { file: uploaded_csv_file }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "queued", body["status"]
    assert_equal "job-file-123", body["job_id"]
    assert_equal 77, body["uploaded_document_id"]
  end

  test "process_file returns bad request when command raises validation error" do
    command = FakeCommand.new(error: DocumentProcessing::UploadManager::ValidationError.new("Formato non supportato"))

    DocumentProcessing::Commands::InitializeFileProcessing.stub(:new, command) do
      post process_file_documents_path, params: { file: uploaded_csv_file }
    end

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "error", body["status"]
    assert_equal "Formato non supportato", body["message"]
  end

  test "process_file returns already_exists when command indicates dedup" do
    command = FakeCommand.new(
      result: {
        status: "already_exists",
        message: "Documento gia caricato; riutilizzo documento esistente",
        job_id: nil,
        uploaded_document_id: 99
      }
    )

    DocumentProcessing::Commands::InitializeFileProcessing.stub(:new, command) do
      post process_file_documents_path, params: { file: uploaded_csv_file }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "already_exists", body["status"]
    assert_nil body["job_id"]
    assert_equal 99, body["uploaded_document_id"]
  end

  test "process_file rejects pdf on generic endpoint" do
    command = FakeCommand.new(error: DocumentProcessing::UploadManager::ValidationError.new("Per i PDF usa l'endpoint /documents/split"))

    DocumentProcessing::Commands::InitializeFileProcessing.stub(:new, command) do
      post process_file_documents_path, params: { file: uploaded_pdf_file }
    end

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "error", body["status"]
    assert_equal "Per i PDF usa l'endpoint /documents/split", body["message"]
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

  test "uploaded_file downloads original csv source" do
    temp = Tempfile.new(["source", ".csv"])
    temp.write("recipient,amount\nMario,10\n")
    temp.rewind

    uploaded_document = UploadedDocument.create!(
      original_filename: "source.csv",
      storage_path: temp.path,
      page_count: 1,
      checksum: "csv-download-checksum",
      file_kind: "csv"
    )

    get uploaded_document_file_path(id: uploaded_document.id)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.headers["Content-Disposition"], "source.csv"
  ensure
    temp.close! if temp
  end

  test "uploads includes file_kind" do
    UploadedDocument.create!(
      original_filename: "img.png",
      storage_path: "/tmp/img.png",
      page_count: 1,
      checksum: "img-kind-checksum",
      file_kind: "image"
    )

    get uploaded_documents_path

    assert_response :success
    body = JSON.parse(response.body)
    first = body["uploaded_documents"].first
    assert_includes ["image", "csv", "pdf", nil], first["file_kind"]
  end

  private

  def uploaded_pdf_file
    temp = Tempfile.new(["upload", ".pdf"])
    temp.binmode
    temp.write("%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF")
    temp.rewind
    Rack::Test::UploadedFile.new(temp.path, "application/pdf", original_filename: "document.pdf")
  end

  def uploaded_csv_file
    temp = Tempfile.new(["upload", ".csv"])
    temp.binmode
    temp.write("recipient,amount\nMario Rossi,100\n")
    temp.rewind
    Rack::Test::UploadedFile.new(temp.path, "text/csv", original_filename: "document.csv")
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