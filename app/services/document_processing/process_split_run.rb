module DocumentProcessing
  class ProcessSplitRun
    def initialize(container:)
      @container = container
    end

    def call(file_path:, job_id:)
      run = ProcessingRun.find_by!(job_id: job_id)
      run.update!(status: "splitting", started_at: Time.current)

      pdf = CombinePDF.load(file_path)
      split_results = container.pdf_splitter(pdf: pdf).split

      create_processing_items_and_enqueue(split_results, run)

      run.update!(
        status: split_results.empty? ? "completed" : "processing",
        total_documents: split_results.size,
        processed_documents: 0,
        completed_at: (split_results.empty? ? Time.current : nil)
      )

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
      run&.update(status: "failed", error_message: e.message, completed_at: Time.current)
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
      ProcessingRun.transaction do
        split_results.each_with_index do |result, index|
          range = result[:range]
          mini_pdf_path = result[:path]

          extracted_document = run.uploaded_document&.extracted_documents&.create!(
            sequence: index + 1,
            page_start: range[:start] + 1,
            page_end: range[:end] + 1,
            status: "queued"
          )

          item = run.processing_items.create!(
            sequence: index + 1,
            filename: File.basename(mini_pdf_path),
            status: "queued",
            extracted_document: extracted_document
          )

          data_extraction_job_class.perform_later(
            mini_pdf_path,
            {
              job_id: run.job_id,
              processing_item_id: item.id,
              extracted_document_id: extracted_document&.id
            }
          )
        end
      end
    end

    def cleanup_source_pdf(file_path, run)
      return unless file_path.present? && File.exist?(file_path)

      source_path = run&.uploaded_document&.storage_path
      return if source_path.present? && File.expand_path(source_path) == File.expand_path(file_path)

      File.delete(file_path)
    end

    def data_extraction_job_class
      DataExtractionJob
    end
  end
end