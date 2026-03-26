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
        return unless item

        item.with_lock do
          item.reload
          item.update!(status: "done", error_message: nil) unless item.done?

          if resolution&.matched?
            extracted = item.extracted_document
            extracted&.with_lock do
              extracted.reload
              extracted.update!(matched_employee: resolution.employee)
            end
          end
        end
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

        extracted_document.with_lock do
          extracted_document.reload
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
      end

      def mark_extracted_document_failed(extracted_document:, error_message:)
        extracted_document&.update(status: "failed", error_message: error_message)
      end

      def update_progress!(run)
        return { completed: false } if run.nil?

        run.with_lock do
          run.reload
          done = run.processing_items.where(status: %w[done failed]).count
          total = run.total_documents

          run.update!(processed_documents: done)

          completed = done.present? && total.present? && done == total
          run.update!(status: "completed", completed_at: Time.current) if completed

          { completed: completed }
        end
      end
      # Generic file repository compatibility methods used by ProcessGenericFile
      def find_uploaded_document(id)
        UploadedDocument.find_by(id: id)
      end

      def mark_run_processing!(run)
        return unless run

        run.with_lock do
          run.reload
          run.update!(status: "processing", started_at: Time.current)
        end
      end

      def set_run_total!(run, total)
        return unless run

        run.with_lock do
          run.reload
          run.update!(total_documents: total)
        end
      end

      def create_csv_item!(uploaded_document:, run:, sequence:, metadata:, confidence:, recipient:, employee:)
        extracted = uploaded_document.extracted_documents.create!(
          sequence: sequence,
          page_start: 1,
          page_end: 1,
          status: "done",
          metadata: metadata,
          recipient: recipient,
          confidence: confidence,
          processed_at: Time.current,
          matched_employee: employee
        )

        item = run.processing_items.create!(
          sequence: sequence,
          filename: "#{uploaded_document.original_filename}-row#{sequence}",
          status: "done",
          extracted_document: extracted
        )

        [extracted, item]
      end

      def create_image_item!(uploaded_document:, run:, metadata:, confidence:, recipient:, employee:)
        extracted = uploaded_document.extracted_documents.create!(
          sequence: 1,
          page_start: 1,
          page_end: 1,
          status: "done",
          metadata: metadata,
          recipient: recipient,
          confidence: confidence,
          processed_at: Time.current,
          matched_employee: employee
        )

        item = run.processing_items.create!(
          sequence: 1,
          filename: uploaded_document.original_filename,
          status: "done",
          extracted_document: extracted
        )

        [extracted, item]
      end

      def mark_run_completed!(run, processed_documents:)
        return unless run

        run.with_lock do
          run.reload
          run.update!(processed_documents: processed_documents, status: "completed", completed_at: Time.current)
        end
      end

      def mark_run_failed!(run, error_message:)
        run&.update(status: "failed", error_message: error_message, completed_at: Time.current)
      end

      def reload_run(run)
        run.reload
      end

      def transaction(&block)
        ProcessingRun.transaction(&block)
      end
    end
  end
end