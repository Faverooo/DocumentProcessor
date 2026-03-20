module DocumentProcessing
  module Persistence
    class SplitRunRepository
      def find_run_by_job_id!(job_id)
        ProcessingRun.find_by!(job_id: job_id)
      end

      def mark_splitting!(run)
        run.update!(status: "splitting", started_at: Time.current)
      end

      def create_split_artifacts!(run:, split_results:)
        created = []

        ProcessingRun.transaction do
          split_results.each_with_index do |result, index|
            created << create_item_for_result!(run:, result:, sequence: index + 1)
          end
        end

        created
      end

      def mark_post_split_state!(run:, split_count:)
        run.update!(
          status: split_count.zero? ? "completed" : "processing",
          total_documents: split_count,
          processed_documents: 0,
          completed_at: (split_count.zero? ? Time.current : nil)
        )
      end

      def mark_failed(run:, error_message:)
        run&.update(status: "failed", error_message: error_message, completed_at: Time.current)
      end

      def uploaded_source_path_for(run)
        run&.uploaded_document&.storage_path
      end

      private

      def create_item_for_result!(run:, result:, sequence:)
        range = result[:range]
        mini_pdf_path = result[:path]

        extracted_document = run.uploaded_document&.extracted_documents&.create!(
          sequence: sequence,
          page_start: range[:start] + 1,
          page_end: range[:end] + 1,
          status: "queued"
        )

        item = run.processing_items.create!(
          sequence: sequence,
          filename: File.basename(mini_pdf_path),
          status: "queued",
          extracted_document: extracted_document
        )

        {
          path: mini_pdf_path,
          processing_item_id: item.id,
          extracted_document_id: extracted_document&.id
        }
      end
    end
  end
end