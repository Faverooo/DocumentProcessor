class PdfSplitJob < ApplicationJob
  queue_as :default

  def perform(file_path, job_id)
    pdf = CombinePDF.load(file_path)
    mini_pdfs = DocumentPdfSplitterService.new(
      pdf:,
      ocr_service: DocumentOcrService.new,
      bedrock_client: bedrock_client
    ).split

    broadcast_result(job_id, status: "success", original_pages: pdf.pages.size, mini_pdfs_count: mini_pdfs.size, mini_pdfs: mini_pdfs.map { |p| File.basename(p) })
  rescue StandardError => e
    broadcast_result(job_id, status: "error", message: e.message)
  ensure
    File.delete(file_path) if file_path && File.exist?(file_path)
  end

  private

  def broadcast_result(job_id, data)
    ActionCable.server.broadcast("document_processing:#{job_id}", data)
  end

  def bedrock_client
    Aws::BedrockRuntime::Client.new(region: aws_region)
  end

  def aws_region
    ENV.fetch("AWS_REGION", "us-east-1")
  end
end
