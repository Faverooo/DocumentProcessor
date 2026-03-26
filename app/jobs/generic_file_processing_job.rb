class GenericFileProcessingJob < ApplicationJob
  queue_as :data

  def perform(file_path, job_context)
    context = normalize_context(job_context)
    container = DocumentProcessing::Container.new

    container.process_generic_file_service.call(
      file_path: file_path,
      job_id: context[:job_id],
      uploaded_document_id: context[:uploaded_document_id],
      file_kind: context[:file_kind]
    )
  end

  private

  def normalize_context(job_context)
    {
      job_id: job_context[:job_id] || job_context["job_id"],
      uploaded_document_id: job_context[:uploaded_document_id] || job_context["uploaded_document_id"],
      file_kind: job_context[:file_kind] || job_context["file_kind"]
    }
  end
end
