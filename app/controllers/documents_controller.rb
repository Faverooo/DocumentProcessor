require "fileutils"

class DocumentsController < ApplicationController
  MAX_PDF_SIZE = 50.megabytes
  ALLOWED_PDF_CONTENT_TYPES = [
    "application/pdf",
    "application/x-pdf",
    "application/acrobat",
    "applications/vnd.pdf",
    "text/pdf",
    "text/x-pdf",
    "application/octet-stream"
  ].freeze

  # GET /documents/test
  def test
  end

  # POST /documents/test_split
  def test_split
    file = params[:pdf]
    return render_error("Nessun file selezionato") unless file.present?

    validation_error = validate_pdf_upload(file)
    return render_error(validation_error) if validation_error

    source_path = persist_uploaded_pdf(file)
    return render_error("Errore nel salvataggio del file") unless source_path

    page_count = CombinePDF.load(source_path).pages.size
    uploaded_document = UploadedDocument.create!(
      original_filename: file.original_filename,
      storage_path: source_path,
      page_count: page_count,
      category: params[:category],
      override_company: params[:company],
      override_department: params[:department],
      competence_period: params[:competence_period]
    )

    job_id = SecureRandom.uuid
    ProcessingRun.create!(
      job_id: job_id,
      status: "queued",
      original_filename: file.original_filename,
      uploaded_document: uploaded_document
    )

    pdf_split_job_class.perform_later(source_path, job_id)

    render json: {
      status: "queued",
      message: "Pipeline avviata: split in corso, processamento documenti automatico",
      job_id: job_id,
      uploaded_document_id: uploaded_document.id
    }
  rescue StandardError => e
    render_error("Errore: #{e.message}")
  end

  # POST /documents/test_data
  def test_data
    with_temp_pdf do |temp_path|
      job_id = SecureRandom.uuid
      run = ProcessingRun.create!(
        job_id: job_id,
        status: "processing",
        original_filename: params[:pdf].original_filename,
        total_documents: 1,
        started_at: Time.current
      )
      item = run.processing_items.create!(
        sequence: 1,
        filename: File.basename(temp_path),
        status: "queued"
      )

      data_extraction_job_class.perform_later(
        temp_path,
        {
          job_id: job_id,
          processing_item_id: item.id
        }
      )
      
      render json: {
        status: "queued",
        message: "Data extraction job enqueued",
        job_id: job_id
      }
    end
  end

  # GET /documents/uploads/:uploaded_document_id/extracted
  def extracted_index
    uploaded_document = UploadedDocument.includes(extracted_documents: :matched_employee).find(params[:uploaded_document_id])

    render json: {
      uploaded_document: {
        id: uploaded_document.id,
        original_filename: uploaded_document.original_filename,
        page_count: uploaded_document.page_count,
        created_at: uploaded_document.created_at
      },
      extracted_documents: uploaded_document.extracted_documents.order(:sequence).map { |doc| extracted_document_payload(doc) }
    }
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", message: "Documento sorgente non trovato" }, status: :not_found
  end

  # GET /documents/extracted/:id
  def extracted_show
    extracted_document = ExtractedDocument.includes(:matched_employee).find(params[:id])
    render json: { extracted_document: extracted_document_payload(extracted_document) }
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", message: "Documento estratto non trovato" }, status: :not_found
  end

  # GET /documents/extracted/:id/pdf
  def extracted_pdf
    extracted_document = ExtractedDocument.find(params[:id])
    source_path = extracted_document.uploaded_document.storage_path
    return render_error("PDF sorgente non disponibile") unless File.exist?(source_path)

    temp_pdf_path = page_range_pdf_service(source_path).build_temp_pdf(
      page_start: extracted_document.page_start,
      page_end: extracted_document.page_end
    )

    filename = "estratto_#{extracted_document.id}_p#{extracted_document.page_start}-#{extracted_document.page_end}.pdf"
    send_data File.binread(temp_pdf_path), filename: filename, type: "application/pdf", disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", message: "Documento estratto non trovato" }, status: :not_found
  rescue ArgumentError => e
    render_error(e.message)
  ensure
    File.delete(temp_pdf_path) if defined?(temp_pdf_path) && temp_pdf_path && File.exist?(temp_pdf_path)
  end

  # PATCH /documents/extracted/:id/reassign_range
  def reassign_range
    extracted_document = ExtractedDocument.find(params[:id])
    page_start, page_end = parse_range_params
    return render_error("Range pagine non valido") if page_start.nil? || page_end.nil?
    return render_error("Range pagine non valido") if page_start <= 0 || page_end <= 0 || page_end < page_start

    uploaded_document = extracted_document.uploaded_document
    if page_end > uploaded_document.page_count
      return render_error("Range oltre il numero di pagine disponibili (max #{uploaded_document.page_count})")
    end

    extracted_document.update!(
      page_start: page_start,
      page_end: page_end,
      status: "queued",
      metadata: {},
      recipients: [],
      fallback_text: nil,
      confidence: {},
      recipient_name: nil,
      matched_employee: nil,
      error_message: nil,
      processed_at: nil
    )

    source_path = uploaded_document.storage_path
    return render_error("PDF sorgente non disponibile") unless File.exist?(source_path)

    temp_pdf_path = page_range_pdf_service(source_path).build_temp_pdf(
      page_start: page_start,
      page_end: page_end
    )
    data_extraction_job_class.perform_later(
      temp_pdf_path,
      {
        extracted_document_id: extracted_document.id
      }
    )

    render json: {
      status: "queued",
      message: "Riassegnazione completata, analisi rilanciata",
      extracted_document_id: extracted_document.id,
      page_start: page_start,
      page_end: page_end
    }
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", message: "Documento estratto non trovato" }, status: :not_found
  rescue ArgumentError => e
    render_error(e.message)
  end

  private

  def with_temp_pdf # serve per gestire in modo sicuro il file caricato, validarlo, salvarlo temporaneamente e assicurarsi che venga cancellato dopo l'uso
    file = params[:pdf]
    return render_error("Nessun file selezionato") unless file.present?

    validation_error = validate_pdf_upload(file)
    return render_error(validation_error) if validation_error

    temp_path = save_temp_file(file)
    return render_error("Errore nel salvataggio del file") unless temp_path

    yield temp_path
  rescue StandardError => e
    render_error("Errore: #{e.message}")
  end

  def save_temp_file(file)
    temp_dir = Rails.root.join("tmp", "uploads")
    FileUtils.mkdir_p(temp_dir)

    safe_name = sanitized_original_filename(file.original_filename)
    temp_path = temp_dir.join("#{Time.current.to_i}_#{SecureRandom.hex(6)}_#{safe_name}")

    file.tempfile.rewind if file.respond_to?(:tempfile) && file.tempfile.respond_to?(:rewind)
    file.rewind if file.respond_to?(:rewind)
    File.binwrite(temp_path, file.read)
    temp_path.to_s
  end

  def persist_uploaded_pdf(file)
    storage_dir = Rails.root.join("storage", "uploads", "source_documents")
    FileUtils.mkdir_p(storage_dir)

    safe_name = sanitized_original_filename(file.original_filename)
    storage_path = storage_dir.join("#{Time.current.to_i}_#{SecureRandom.hex(8)}_#{safe_name}")

    file.tempfile.rewind if file.respond_to?(:tempfile) && file.tempfile.respond_to?(:rewind)
    file.rewind if file.respond_to?(:rewind)
    File.binwrite(storage_path, file.read)
    storage_path.to_s
  end

  def validate_pdf_upload(file)
    return "Il file deve avere estensione .pdf" unless file.original_filename.to_s.downcase.end_with?(".pdf")
    return "File troppo grande (max 50 MB)" if file_size(file) > MAX_PDF_SIZE

    content_type = file.content_type.to_s.downcase
    return "Formato non valido: carica un PDF" unless ALLOWED_PDF_CONTENT_TYPES.include?(content_type)
    return "Contenuto file non valido: il file non sembra un PDF" unless pdf_signature_valid?(file)

    nil
  end

  def file_size(file)
    return file.size.to_i if file.respond_to?(:size)
    return file.tempfile.size.to_i if file.respond_to?(:tempfile) && file.tempfile.respond_to?(:size)

    0
  end

  def pdf_signature_valid?(file) # serve per evitare di processare file che non sono realmente PDF anche se hanno estensione e content type corretti
    io = file.respond_to?(:tempfile) ? file.tempfile : file
    return false unless io.respond_to?(:read)

    io.rewind if io.respond_to?(:rewind)
    signature = io.read(5)
    io.rewind if io.respond_to?(:rewind)
    signature == "%PDF-"
  rescue StandardError
    false
  end

  def sanitized_original_filename(name) # serve per evitare problemi di path traversal o caratteri strani nei nomi dei file
    basename = File.basename(name.to_s)
    sanitized = basename.gsub(/[^0-9A-Za-z.\-_]/, "_")
    sanitized = "upload.pdf" if sanitized.blank?
    sanitized = "#{sanitized}.pdf" unless sanitized.downcase.end_with?(".pdf")
    sanitized
  end

  def parse_range_params
    if params[:page_range].present?
      match = params[:page_range].to_s.strip.match(/\A(\d+)\s*[-:]\s*(\d+)\z/)
      return [nil, nil] unless match

      return [match[1].to_i, match[2].to_i]
    end

    start_page = integer_or_nil(params[:page_start])
    end_page = integer_or_nil(params[:page_end])
    return [nil, nil] if start_page.nil? || end_page.nil?

    [start_page, end_page]
  end

  def integer_or_nil(value)
    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  def extracted_document_payload(document)
    {
      id: document.id,
      uploaded_document_id: document.uploaded_document_id,
      sequence: document.sequence,
      status: document.status,
      page_start: document.page_start,
      page_end: document.page_end,
      metadata: document.metadata,
      recipients: document.recipients,
      confidence: document.confidence,
      recipient_name: document.recipient_name,
      matched_employee: format_employee(document.matched_employee),
      error_message: document.error_message,
      processed_at: document.processed_at,
      document_type: document.document_type,
      process_time_seconds: document.process_time_seconds,
      created_at: document.created_at,
      updated_at: document.updated_at,
      pdf_download_url: extracted_pdf_document_url(id: document.id)
    }
  end

  def format_employee(employee)
    return nil unless employee

    {
      id: employee.id,
      name: employee.name,
      email: employee.email,
      employee_code: employee.employee_code
    }
  end

  def render_error(message)
    render json: { status: "error", message: }, status: :bad_request
  end

  def page_range_pdf_service(source_pdf_path)
    page_range_pdf_service_class.new(source_pdf_path: source_pdf_path)
  end

  def page_range_pdf_service_class
    DocumentPageRangePdfService
  end

  def data_extraction_job_class
    DataExtractionJob
  end

  def pdf_split_job_class
    PdfSplitJob
  end
end
