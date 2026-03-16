module DocumentProcessing
  class ProcessSplitRun
    def initialize(container:)
      @container = container
    end

    def call(file_path:, job_id:)
      run = ProcessingRun.find_by!(job_id: job_id)
      run.update!(status: "splitting", started_at: Time.current)

      pdf = CombinePDF.load(file_path)
      mini_pdfs = container.pdf_splitter(pdf: pdf).split

      create_processing_items_and_enqueue(mini_pdfs, run)

      run.update!(
        status: mini_pdfs.empty? ? "completed" : "processing",
        total_documents: mini_pdfs.size,
        processed_documents: 0,
        completed_at: (mini_pdfs.empty? ? Time.current : nil)
      )

      notifier.broadcast(
        job_id,
        event: "split_completed",
        status: "success",
        original_pages: pdf.pages.size,
        mini_pdfs_count: mini_pdfs.size,
        mini_pdfs: mini_pdfs.map { |p| File.basename(p) }
      )

      return unless mini_pdfs.empty?

      notifier.broadcast(
        job_id,
        event: "processing_completed",
        status: "success"
      )
    rescue StandardError => e
      run&.update(status: "failed", error_message: e.message, completed_at: Time.current)
      notifier.broadcast(job_id, event: "split_completed", status: "error", message: e.message)
    ensure
      File.delete(file_path) if file_path && File.exist?(file_path)
    end

    private

    attr_reader :container

    def notifier
      container.notifier
    end

    def create_processing_items_and_enqueue(mini_pdfs, run)
      ProcessingRun.transaction do
        mini_pdfs.each_with_index do |mini_pdf_path, index|
          item = run.processing_items.create!(
            sequence: index + 1,
            filename: File.basename(mini_pdf_path),
            status: "queued"
          )

          RecipientExtractionJob.perform_later(mini_pdf_path, run.job_id, item.id)
        end
      end
    end
  end
end