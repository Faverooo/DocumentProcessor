class DataExtractionJob < ApplicationJob
  queue_as :data

  def perform(file_path, job_context = nil, processing_item_id = nil, extracted_document_id = nil)
    options = normalize_options(job_context, processing_item_id, extracted_document_id)

    container = DocumentProcessing::Container.new
    container.process_data_item_service.call(
      file_path:,
      job_id: options[:job_id],
      processing_item_id: options[:processing_item_id],
      extracted_document_id: options[:extracted_document_id]
    )
  end

  private

  def normalize_options(job_context, processing_item_id, extracted_document_id)
    if job_context.is_a?(Hash)
      {
        job_id: job_context[:job_id] || job_context["job_id"],
        processing_item_id: job_context[:processing_item_id] || job_context["processing_item_id"],
        extracted_document_id: job_context[:extracted_document_id] || job_context["extracted_document_id"]
      }
    else
      {
        job_id: job_context,
        processing_item_id: processing_item_id,
        extracted_document_id: extracted_document_id
      }
    end
  end

end