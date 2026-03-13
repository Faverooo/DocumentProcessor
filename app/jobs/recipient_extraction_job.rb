class RecipientExtractionJob < ApplicationJob
  queue_as :recipient

  def perform(file_path, job_id, processing_item_id = nil, total_documents = nil)
    container = DocumentProcessing::Container.new
    run = ProcessingRun.find_by(job_id: job_id)
    item = processing_item_id ? ProcessingItem.find_by(id: processing_item_id) : nil
    item&.update!(status: "in_progress")

    ocr_service = container.ocr_service
    extractor = container.recipient_extractor
    resolver = container.recipient_resolver

    full_text = ocr_service.full_ocr(file_path)
    recipient_names = extractor.extract(full_text)
    matched_recipient = resolver.resolve(recipient_names:, raw_text: full_text)

    persist_processed_document(file_path, matched_recipient)
    item&.update!(
      status: "done",
      recipient_name: matched_recipient.is_a?(Employee) ? matched_recipient.name : nil,
      matched_employee: matched_recipient.is_a?(Employee) ? matched_recipient : nil,
      error_message: nil
    )

    container.broadcast(
      job_id,
      event: "document_processed",
      status: "success",
      document_index: item&.sequence,
      total_documents: resolved_total(run, total_documents),
      filename: File.basename(file_path),
      ocr_text: full_text,
      extracted_names: recipient_names,
      matched_recipient: format_employee(matched_recipient),
      fallback_text: matched_recipient.is_a?(String) ? matched_recipient : nil
    )
  rescue StandardError => e
    item&.update(status: "failed", error_message: e.message)
    container.broadcast(
      job_id,
      event: "document_processed",
      status: "error",
      document_index: item&.sequence,
      total_documents: resolved_total(run, total_documents),
      filename: File.basename(file_path),
      message: e.message
    )
  ensure
    increment_progress(container, run, job_id)
    File.delete(file_path) if file_path && File.exist?(file_path)
  end

  private

  def persist_processed_document(file_path, matched_recipient)
    return unless matched_recipient.is_a?(Employee)

    ProcessedDocument.create!(
      filename: File.basename(file_path),
      status: "processed",
      recipient_name: matched_recipient.name,
      employee: matched_recipient
    )
  end

  def increment_progress(container, run, job_id)
    return if run.nil?

    done = run.processing_items.where(status: %w[done failed]).count
    total = run.total_documents

    run.update!(processed_documents: done)

    return if done.nil? || total.nil? || done != total

    run.update!(status: "completed", completed_at: Time.current)

    container.broadcast(
      job_id,
      event: "processing_completed",
      status: "success",
      processed_documents: done,
      total_documents: total
    )
  end

  def resolved_total(run, total_documents)
    total_documents || run&.total_documents
  end

  def format_employee(obj)
    return nil unless obj.is_a?(Employee)
    { id: obj.id, name: obj.name, email: obj.email, employee_code: obj.employee_code }
  end
end
