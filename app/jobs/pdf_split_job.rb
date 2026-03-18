class PdfSplitJob < ApplicationJob
  queue_as :split

  def perform(file_path, job_id)
    container = DocumentProcessing::Container.new
    process_split_run_service.new(container:).call(file_path:, job_id:)
  end

  private

  def process_split_run_service
    DocumentProcessing::ProcessSplitRun
  end
end
