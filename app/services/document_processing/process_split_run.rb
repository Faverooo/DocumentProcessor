module DocumentProcessing
  class ProcessSplitRun
    def initialize(container:)
      @container = container
    end

    def call(file_path:, job_id:)
      run = split_run_repository.find_run_by_job_id!(job_id)
      split_run_repository.mark_splitting!(run)

      pdf = CombinePDF.load(file_path)
      split_results = container.pdf_splitter(pdf: pdf).split

      create_processing_items_and_enqueue(split_results, run)

      split_run_repository.mark_post_split_state!(run:, split_count: split_results.size)

      notifier.broadcast(
        job_id,
        event: "split_completed",
        status: "success",
        original_pages: pdf.pages.size,
        mini_pdfs_count: split_results.size,
        mini_pdfs: split_results.map { |result| File.basename(result[:path]) }
      )

      return unless split_results.empty?

      notifier.broadcast(
        job_id,
        event: "processing_completed",
        status: "success"
      )
    rescue StandardError => e
      split_run_repository.mark_failed(run:, error_message: e.message)
      notifier.broadcast(job_id, event: "split_completed", status: "error", message: e.message)
    ensure
      cleanup_source_pdf(file_path, run)
    end

    private

    attr_reader :container

    def notifier
      container.notifier
    end

    def create_processing_items_and_enqueue(split_results, run)
      created_artifacts = split_run_repository.create_split_artifacts!(run:, split_results:)

      created_artifacts.each do |artifact|
        data_extraction_job_class.perform_later(
          artifact[:path],
          {
            job_id: run.job_id,
            processing_item_id: artifact[:processing_item_id],
            extracted_document_id: artifact[:extracted_document_id]
          }
        )
      end
    end

    def cleanup_source_pdf(file_path, run)
      return unless file_path.present? && file_storage.exist?(file_path)

      source_path = split_run_repository.uploaded_source_path_for(run)
      return if source_path.present? && file_storage.expanded(source_path) == file_storage.expanded(file_path)

      file_storage.delete(file_path)
    end

    def data_extraction_job_class
      DataExtractionJob
    end

    def split_run_repository
      container.split_run_repository
    end

    def file_storage
      container.file_storage
    end
  end
end