class DocumentsController < ApplicationController
  # GET /documents/test
  def test
  end

  # POST /documents/test_split
  def test_split
    with_temp_pdf do |temp_path|
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

  # POST /documents/test_recipient
  def test_recipient
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

      RecipientExtractionJob.perform_later(temp_path, job_id, item.id)
      
      render json: {
        status: "queued",
        message: "Recipient extraction job enqueued",
        job_id: job_id
      }
    end
  end

  private

  def with_temp_pdf
    return render_error("Nessun file selezionato") unless params[:pdf].present?
    
    temp_path = save_temp_file(params[:pdf])
    return render_error("Errore nel salvataggio del file") unless temp_path

    yield temp_path
  rescue StandardError => e
    render_error("Errore: #{e.message}")
  end

  def save_temp_file(file)
    temp_dir = Rails.root.join("tmp", "uploads")
    Dir.mkdir(temp_dir) unless Dir.exist?(temp_dir)
    
    temp_path = temp_dir.join("#{Time.current.to_i}_#{file.original_filename}")
    File.binwrite(temp_path, file.read)
    temp_path.to_s
  end

  def render_error(message)
    render json: { status: "error", message: }, status: :bad_request
  end
end
