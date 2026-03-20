module DocumentProcessing
  module Commands
    class EnqueueSingleDataExtraction
      def initialize(
        upload_manager: DocumentProcessing::UploadManager.new,
        data_extraction_job_class: DataExtractionJob
      )
        @upload_manager = upload_manager
        @data_extraction_job_class = data_extraction_job_class
      end

      def call(file:)
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
          job_id: job_id,
          message: "Data extraction job enqueued"
        }
      end

      private

      attr_reader :upload_manager, :data_extraction_job_class
    end
  end
end