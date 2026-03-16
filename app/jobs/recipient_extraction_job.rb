class RecipientExtractionJob < ApplicationJob
  queue_as :recipient

  def perform(file_path, job_id, processing_item_id = nil)
    container = DocumentProcessing::Container.new
    DocumentProcessing::ProcessRecipientItem.new(container:).call(
      file_path:,
      job_id:,
      processing_item_id:
    )
  end
end
