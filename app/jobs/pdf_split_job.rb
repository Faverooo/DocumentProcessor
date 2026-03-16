class PdfSplitJob < ApplicationJob
  queue_as :split

  def perform(file_path, job_id)
    container = DocumentProcessing::Container.new
    DocumentProcessing::ProcessSplitRun.new(container:).call(file_path:, job_id:)
  end
end
