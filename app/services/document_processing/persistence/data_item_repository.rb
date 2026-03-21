module DocumentProcessing
  module Persistence
    class DataItemRepository
      def find_run_by_job_id(job_id)
        ProcessingRun.find_by(job_id: job_id)
      end

      def find_processing_item(id)
        ProcessingItem.find_by(id: id)
      end

      def find_extracted_document(id)
        ExtractedDocument.find_by(id: id)
      end

      def terminal_item?(item)
        return false unless item

        item.with_lock do
          item.reload
          item.done? || item.failed?
        end
      end

      def mark_item_in_progress!(item)
        return unless item

        item.with_lock do
          item.reload
          item.update!(status: "in_progress") unless item.done? || item.failed?
        end
      end

      def mark_item_done!(item:, resolution:)
        item&.update!(
          status: "done",
          matched_employee: resolution.matched? ? resolution.employee : nil,
          error_message: nil
        )
      end

      def mark_item_failed(item:, error_message:)
        item&.update(status: "failed", error_message: error_message)
      end

      def mark_extracted_document_in_progress!(extracted_document)
        return unless extracted_document

        extracted_document.with_lock do
          extracted_document.reload
          extracted_document.update!(status: "in_progress") unless extracted_document.done? || extracted_document.failed?
        end
      end

      def mark_extracted_document_done!(
        extracted_document:,
        resolution:,
        metadata:,
        recipient:,
        global_confidence:,
        process_duration_seconds:
      )
        return unless extracted_document

        extracted_document.update!(
          status: "done",
          metadata: metadata,
          recipient: recipient,
          confidence: global_confidence,
          process_time_seconds: process_duration_seconds.to_f,
          matched_employee: resolution.matched? ? resolution.employee : nil,
          error_message: nil,
          processed_at: Time.current
        )
      end

      def mark_extracted_document_failed(extracted_document:, error_message:)
        extracted_document&.update(status: "failed", error_message: error_message)
      end

      def update_progress!(run)
        return { completed: false } if run.nil?

        done = run.processing_items.where(status: %w[done failed]).count
        total = run.total_documents

        run.update!(processed_documents: done)

        completed = done.present? && total.present? && done == total
        run.update!(status: "completed", completed_at: Time.current) if completed

        { completed: completed }
      end
    end
  end
end