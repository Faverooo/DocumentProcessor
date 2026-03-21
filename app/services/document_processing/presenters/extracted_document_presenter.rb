module DocumentProcessing
  module Presenters
    class ExtractedDocumentPresenter
      def initialize(document, url_helpers: Rails.application.routes.url_helpers)
        @document = document
        @url_helpers = url_helpers
      end

      def as_json(*)
        {
          id: document.id,
          uploaded_document_id: document.uploaded_document_id,
          sequence: document.sequence,
          status: document.status,
          page_start: document.page_start,
          page_end: document.page_end,
          metadata: document.metadata,
          recipient: document.recipient,
          confidence: document.confidence,
          matched_employee: format_employee(document.matched_employee),
          error_message: document.error_message,
          processed_at: document.processed_at,
          process_time_seconds: document.process_time_seconds,
          created_at: document.created_at,
          updated_at: document.updated_at,
          pdf_download_url: url_helpers.extracted_pdf_document_path(id: document.id)
        }
      end

      private

      attr_reader :document, :url_helpers

      # `document_type` removed: rely on `metadata['type']` only

      def format_employee(employee)
        return nil unless employee

        {
          id: employee.id,
          name: employee.name,
          email: employee.email,
          employee_code: employee.employee_code
        }
      end
    end
  end
end
