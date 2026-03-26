module DocumentProcessing
  module Commands
    class ReassignExtractedRange
      class ValidationError < StandardError; end

      def initialize(
        page_range_pdf_service_class:,
        data_extraction_job_class:,
        file_storage:
      )
        @page_range_pdf_service_class = page_range_pdf_service_class
        @data_extraction_job_class = data_extraction_job_class
        @file_storage = file_storage
      end

      def call(extracted_document_id:, page_start:, page_end:)
        begin
          extracted_document = ExtractedDocument.find(extracted_document_id)
          validate_range_values!(page_start:, page_end:)

          uploaded_document = extracted_document.uploaded_document
          validate_range_within_document!(page_end:, uploaded_document:)

          source_path = uploaded_document.storage_path
          return { ok: false, error: :validation, message: "PDF sorgente non disponibile" } unless file_storage.exist?(source_path)

          extracted_document.update!(
            page_start: page_start,
            page_end: page_end,
            status: "queued",
            metadata: {},
            recipient: nil,
            confidence: {},
            matched_employee: nil,
            error_message: nil,
            processed_at: nil
          )

          temp_pdf_path = page_range_pdf_service_class.new(source_pdf_path: source_path).build_temp_pdf(
            page_start: page_start,
            page_end: page_end
          )

          data_extraction_job_class.perform_later(
            temp_pdf_path,
            {
              extracted_document_id: extracted_document.id
            }
          )

          {
            ok: true,
            extracted_document_id: extracted_document.id,
            page_start: page_start,
            page_end: page_end,
            message: "Riassegnazione completata, analisi rilanciata"
          }
        rescue ArgumentError => e
          { ok: false, error: :validation, message: e.message }
        end
      end

      private

      attr_reader :page_range_pdf_service_class, :data_extraction_job_class, :file_storage

      def validate_range_values!(page_start:, page_end:)
        raise ValidationError, "Range pagine non valido" unless page_start.is_a?(Integer) && page_end.is_a?(Integer)
        raise ValidationError, "Range pagine non valido" if page_start <= 0 || page_end <= 0 || page_end < page_start
      end

      def validate_range_within_document!(page_end:, uploaded_document:)
        return unless page_end > uploaded_document.page_count

        raise ValidationError, "Range oltre il numero di pagine disponibili (max #{uploaded_document.page_count})"
      end
    end
  end
end