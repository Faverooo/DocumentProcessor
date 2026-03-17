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
    with_temp_pdf do |temp_path| #salva il file caricato in una posizione temporanea temp_path e poi lo passa al blocco, assicurandosi che venga cancellato dopo l'uso
      job_id = SecureRandom.uuid
      ProcessingRun.create!(
        job_id: job_id,
        status: "queued",
        original_filename: params[:pdf].original_filename
      )

      PdfSplitJob.perform_later(temp_path, job_id)
      
      render json: {
        status: "queued",
        message: "Pipeline avviata: split in corso, processamento documenti automatico",
        job_id: job_id
      }
    end
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

      DataExtractionJob.perform_later(temp_path, job_id, item.id)
      
      render json: {
        status: "queued",
        message: "Data extraction job enqueued",
        job_id: job_id
      }
    end
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

  def render_error(message)
    render json: { status: "error", message: }, status: :bad_request
  end
end
