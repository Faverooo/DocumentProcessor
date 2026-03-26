module DocumentProcessing
  module Commands
    class EnqueueSingleDataExtraction
      def initialize(
        upload_manager:,
        data_extraction_job_class:
      )
        @upload_manager = upload_manager
        @data_extraction_job_class = data_extraction_job_class
      end

      def call(file:)
        temp_path = nil
        begin
          temp_path = upload_manager.persist_temp_pdf(file)
          job_id = SecureRandom.uuid

          run = ProcessingRun.create!(
            job_id: job_id,
            status: "processing",
            original_filename: file.original_filename,
            total_documents: 1,
            started_at: Time.current
          )

          item = run.processing_items.create!(
            sequence: 1,
            filename: File.basename(temp_path),
            status: "queued"
          )

          data_extraction_job_class.perform_later(
            temp_path,
            {
              job_id: job_id,
              processing_item_id: item.id
            }
          )

          {
            ok: true,
            job_id: job_id,
            message: "Data extraction job enqueued"
          }
        rescue DocumentProcessing::UploadManager::ValidationError => e
          { ok: false, error: :validation, message: e.message }
        rescue DocumentProcessing::UploadManager::PersistenceError => _e
          { ok: false, error: :persistence, message: "Errore nel salvataggio del file" }
        end
      end

      private

      attr_reader :upload_manager, :data_extraction_job_class
    end
  end
end