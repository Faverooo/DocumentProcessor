class DocumentProcessorJob < ApplicationJob
  queue_as :default

  def perform(file_path)
    DocumentProcessorService.new(file_path).call
  end
end
