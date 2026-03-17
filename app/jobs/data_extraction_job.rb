class DataExtractionJob < ApplicationJob
  queue_as :data

  def perform(file_path, job_id, processing_item_id = nil)
    container = DocumentProcessing::Container.new
    DocumentProcessing::ProcessDataItem.new(container:).call(
      file_path:,
      job_id:,
      processing_item_id:
    )
  end
end