class RecipientExtractionJob < ApplicationJob
  queue_as :default

  def perform(file_path, job_id)
    ocr_service = DocumentOcrService.new(textract_client: textract_client)
    extractor = DocumentRecipientExtractorService.new(bedrock_client: bedrock_client)
    resolver = DocumentRecipientResolverService.new

    full_text = ocr_service.full_ocr(file_path)
    recipient_names = extractor.extract(full_text)
    matched_recipient = resolver.resolve(recipient_names:, raw_text: full_text)

    broadcast_result(job_id, status: "success", ocr_text: full_text, extracted_names: recipient_names, matched_recipient: format_employee(matched_recipient), fallback_text: matched_recipient.is_a?(String) ? matched_recipient : nil)
  rescue StandardError => e
    broadcast_result(job_id, status: "error", message: e.message)
  ensure
    File.delete(file_path) if file_path && File.exist?(file_path)
  end

  private

  def broadcast_result(job_id, data)
    ActionCable.server.broadcast("document_processing:#{job_id}", data)
  end

  def format_employee(obj)
    return nil unless obj.is_a?(Employee)
    { id: obj.id, name: obj.name, email: obj.email, employee_code: obj.employee_code }
  end

  def textract_client
    Aws::Textract::Client.new(region: aws_region)
  end

  def bedrock_client
    Aws::BedrockRuntime::Client.new(region: aws_region)
  end

  def aws_region
    ENV.fetch("AWS_REGION", "us-east-1")
  end
end
