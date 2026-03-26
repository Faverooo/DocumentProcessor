class DocumentsController < ApplicationController
  # GET /documents/test
  def test
  end

  # POST /documents/split
  def split
    result = initialize_processing_command.call(
      file: params[:pdf],
      category: params[:category],
      company: params[:company],
      department: params[:department],
      competence_period: params[:competence_period]
    )
    if result.is_a?(Hash) && result[:ok] == false
      case result[:error]
      when :validation
        return render_error(result[:message])
      when :persistence
        return render_error("Errore nel salvataggio del file")
      else
        return render_error("Errore: #{result[:message]}")
      end
    end

    render json: {
      status: result[:status] || "queued",
      message: result[:message],
      job_id: result[:job_id],
      uploaded_document_id: result[:uploaded_document_id]
    }
  rescue StandardError => e
    render_error("Errore: #{e.message}")
  end

  # POST /documents/test_data
  def test_data
    result = enqueue_single_data_extraction_command.call(file: params[:pdf])
    if result.is_a?(Hash) && result[:ok] == false
      case result[:error]
      when :validation
        return render_error(result[:message])
      when :persistence
        return render_error("Errore nel salvataggio del file")
      else
        return render_error("Errore: #{result[:message]}")
      end
    end

    render json: {
      status: result[:status] || "queued",
      message: result[:message],
      job_id: result[:job_id]
    }
  rescue StandardError => e
    render_error("Errore: #{e.message}")
  end

  # GET /documents/uploads/:uploaded_document_id/extracted
  def extracted_index
    uploaded_document = UploadedDocument.includes(extracted_documents: :matched_employee).find(params[:uploaded_document_id])

    render json: {
      uploaded_document: {
        id: uploaded_document.id,
        original_filename: uploaded_document.original_filename,
        page_count: uploaded_document.page_count,
        file_kind: uploaded_document.file_kind,
        created_at: uploaded_document.created_at
      },
      extracted_documents: uploaded_document.extracted_documents.order(:sequence).map { |doc| extracted_document_presenter(doc).as_json }
    }
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", message: "Documento sorgente non trovato" }, status: :not_found
  end

  # GET /documents/uploads
  # Restituisce la lista minimale degli uploaded document (id, original_filename, page_count, created_at)
  def uploads
    list = db_manager.uploaded_documents_list
    render json: { uploaded_documents: list }
  end

  # GET /documents/uploads/:id/file
  def uploaded_file
    uploaded_document = UploadedDocument.find(params[:id])
    source_path = uploaded_document.storage_path
    return render_error("File sorgente non disponibile") unless file_storage.exist?(source_path)

    send_file source_path,
              filename: uploaded_document.original_filename,
              type: content_type_for_uploaded(uploaded_document),
              disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", message: "Documento sorgente non trovato" }, status: :not_found
  end

  
  # GET /documents/extracted/:id
  def extracted_show
    extracted_document = ExtractedDocument.includes(:matched_employee).find(params[:id])
    render json: { extracted_document: extracted_document_presenter(extracted_document).as_json }
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", message: "Documento estratto non trovato" }, status: :not_found
  end

  # GET /documents/extracted/:id/pdf
  def extracted_pdf
    extracted_document = ExtractedDocument.find(params[:id])
    source_path = extracted_document.uploaded_document.storage_path
    return render_error("PDF sorgente non disponibile") unless file_storage.exist?(source_path)

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
    file_storage.delete(temp_pdf_path) if defined?(temp_pdf_path) && temp_pdf_path && file_storage.exist?(temp_pdf_path)
  end

  # PATCH /documents/extracted/:id/reassign_range
  def reassign_range
    page_start, page_end = parse_range_params
    return render_error("Range pagine non valido") if page_start.nil? || page_end.nil?
    result = reassign_extracted_range_command.call(
      extracted_document_id: params[:id],
      page_start: page_start,
      page_end: page_end
    )
    if result.is_a?(Hash) && result[:ok] == false
      return render_error(result[:message]) if result[:error] == :validation
      return render_error("Errore: #{result[:message]}")
    end

    render json: {
      status: "queued",
      message: result[:message],
      extracted_document_id: result[:extracted_document_id],
      page_start: result[:page_start],
      page_end: result[:page_end]
    }
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", message: "Documento estratto non trovato" }, status: :not_found
  end

  # PATCH /documents/extracted/:id/metadata
  # Body: { "metadata_updates": { "field1": "value", ... } }
  def update_metadata
    # Support several payload shapes (plain Hash, Parameters, nested document, or JSON string)
    raw = params[:metadata_updates] || params[:metadata] || params.dig(:document, :metadata_updates) || {}
    metadata_updates = if raw.respond_to?(:to_unsafe_h)
      raw.to_unsafe_h
    elsif raw.is_a?(String)
      (JSON.parse(raw) rescue {})
    elsif raw.is_a?(Hash)
      raw
    else
      {}
    end

    unless metadata_updates.is_a?(Hash)
      return render json: { status: "error", message: "metadata_updates must be an object" }, status: :bad_request
    end

    updated = db_manager.update_extracted_metadata(
      extracted_document_id: params[:id],
      metadata_updates: metadata_updates
    )

    render json: { status: "ok", extracted_document: extracted_document_presenter(updated).as_json }
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", message: "Documento estratto non trovato" }, status: :not_found
  rescue ArgumentError => e
    render_error(e.message)
  rescue StandardError => e
    render_error("Errore: #{e.message}")
  end

  # PATCH /documents/extracted/:id/validate
  def validate_extracted
    extracted_document = ExtractedDocument.find(params[:id])

    unless extracted_document.done?
      return render json: { status: "error", message: "Only documents in 'done' state can be validated" }, status: :bad_request
    end

    if extracted_document.update(status: "validated")
      render json: { status: "ok", extracted_document: extracted_document_presenter(extracted_document).as_json }
    else
      render json: { status: "error", message: extracted_document.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { status: "error", message: "Documento estratto non trovato" }, status: :not_found
  end

  # POST /documents/process_file
  # Receives a single file (csv, jpeg, png) and processes it without performing split.
  # Returns: { status: 'ok', job_id: '<uuid>' }
  def process_file
    result = initialize_file_processing_command.call(
      file: params[:file],
      category: params[:category],
      company: params[:company],
      department: params[:department],
      competence_period: params[:competence_period]
    )
    if result.is_a?(Hash) && result[:ok] == false
      case result[:error]
      when :validation
        return render_error(result[:message])
      when :persistence
        return render_error("Errore nel salvataggio del file")
      else
        return render_error("Errore: #{result[:message]}")
      end
    end

    render json: {
      status: result[:status] || "queued",
      message: result[:message],
      job_id: result[:job_id],
      uploaded_document_id: result[:uploaded_document_id]
    }
  rescue StandardError => e
    render_error("Errore: #{e.message}")
  end

  private

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

  def render_error(message)
    render json: { status: "error", message: }, status: :bad_request
  end

  def page_range_pdf_service(source_pdf_path)
    page_range_pdf_service_class.new(source_pdf_path: source_pdf_path)
  end

  def page_range_pdf_service_class
    document_processing_container.page_range_pdf_service_class
  end

  def initialize_processing_command
    document_processing_container.initialize_processing_command
  end

  def initialize_file_processing_command
    document_processing_container.initialize_file_processing_command
  end

  def enqueue_single_data_extraction_command
    document_processing_container.enqueue_single_data_extraction_command
  end

  def reassign_extracted_range_command
    document_processing_container.reassign_extracted_range_command
  end

  def extracted_document_presenter(document)
    extracted_document_presenter_class.new(document)
  end

  def extracted_document_presenter_class
    DocumentProcessing::Presenters::ExtractedDocumentPresenter
  end

  def file_storage
    document_processing_container.file_storage
  end

  def db_manager
    document_processing_container.db_manager
  end

  def document_processing_container
    @document_processing_container ||= DocumentProcessing::Container.new
  end

  def content_type_for_uploaded(uploaded_document)
    case uploaded_document.file_kind
    when "pdf"
      "application/pdf"
    when "csv"
      "text/csv"
    when "image"
      ext = File.extname(uploaded_document.original_filename.to_s).downcase
      return "image/png" if ext == ".png"

      "image/jpeg"
    else
      "application/octet-stream"
    end
  end

end
