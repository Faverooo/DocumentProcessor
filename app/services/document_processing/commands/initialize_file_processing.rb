module DocumentProcessing
  module Commands
    class InitializeFileProcessing
      def initialize(
        upload_manager:,
        generic_file_processing_job_class:,
        file_storage:
      )
        @upload_manager = upload_manager
        @generic_file_processing_job_class = generic_file_processing_job_class
        @file_storage = file_storage
      end

      def call(file:, category: nil, company: nil, department: nil, competence_period: nil)
        source_path = nil
        begin
          kind = upload_manager.detect_upload_kind(file)
          return { ok: false, error: :validation, message: "Formato non supportato" } if kind == :unknown
          return { ok: false, error: :validation, message: "Per i PDF usa l'endpoint /documents/split" } if kind == :pdf

          checksum = upload_manager.compute_checksum(file)
          existing = UploadedDocument.find_by(checksum: checksum)
          if existing
            return {
              ok: true,
              status: "already_exists",
              job_id: nil,
              uploaded_document_id: existing.id,
              message: "Documento gia caricato; riutilizzo documento esistente"
            }
          end

          source_path = upload_manager.persist_supported_source_file(file)
          job_id = SecureRandom.uuid

          uploaded_document = nil
          ProcessingRun.transaction do
            uploaded_document = UploadedDocument.create!(
              original_filename: file.original_filename,
              storage_path: source_path,
              page_count: 1,
              file_kind: kind.to_s,
              category: category,
              override_company: company,
              override_department: department,
              competence_period: competence_period,
              checksum: checksum
            )

            ProcessingRun.create!(
              job_id: job_id,
              status: "queued",
              original_filename: file.original_filename,
              uploaded_document: uploaded_document,
              total_documents: 0,
              processed_documents: 0
            )
          end

          generic_file_processing_job_class.perform_later(
            source_path,
            {
              job_id: job_id,
              uploaded_document_id: uploaded_document.id,
              file_kind: kind.to_s,
              category: category,
              override_company: company,
              override_department: department,
              competence_period: competence_period
            }
          )

          {
            ok: true,
            status: "queued",
            job_id: job_id,
            uploaded_document_id: uploaded_document.id,
            message: "Pipeline avviata: analisi file in coda"
          }
        rescue DocumentProcessing::UploadManager::ValidationError => e
          cleanup_failed_source_file(source_path)
          { ok: false, error: :validation, message: e.message }
        rescue DocumentProcessing::UploadManager::PersistenceError => _e
          cleanup_failed_source_file(source_path)
          { ok: false, error: :persistence, message: "Errore nel salvataggio del file" }
        rescue StandardError => e
          cleanup_failed_source_file(source_path)
          raise e
        end
      end

      private

      attr_reader :upload_manager, :generic_file_processing_job_class, :file_storage

      def cleanup_failed_source_file(path)
        return unless path.present? && file_storage.exist?(path)

        file_storage.delete(path)
      end
    end
  end
end
