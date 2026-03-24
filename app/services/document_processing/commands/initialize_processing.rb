module DocumentProcessing
  module Commands
    class InitializeProcessing
      require "digest"
      def initialize(
        upload_manager: DocumentProcessing::UploadManager.new,
        pdf_split_job_class: PdfSplitJob,
        pdf_loader: CombinePDF,
        file_storage: DocumentProcessing::Persistence::FileStorage.new
      )
        @upload_manager = upload_manager
        @pdf_split_job_class = pdf_split_job_class
        @pdf_loader = pdf_loader
        @file_storage = file_storage
      end

      def call(file:, category: nil, company: nil, department: nil, competence_period: nil)
        checksum = compute_checksum(file)

        existing = UploadedDocument.find_by(checksum: checksum)
        if existing
          return {
            job_id: nil,
            uploaded_document_id: existing.id,
            message: "Documento già caricato; riutilizzo documento esistente"
          }
        end

        source_path = upload_manager.persist_source_pdf(file)
        page_count = pdf_loader.load(source_path).pages.size
        job_id = SecureRandom.uuid

        uploaded_document = nil
        ProcessingRun.transaction do
          uploaded_document = UploadedDocument.create!(
            original_filename: file.original_filename,
            storage_path: source_path,
            page_count: page_count,
            file_kind: "pdf",
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
            uploaded_document: uploaded_document
          )
        end

        pdf_split_job_class.perform_later(source_path, job_id)

        {
          job_id: job_id,
          uploaded_document_id: uploaded_document.id,
          message: "Pipeline avviata: split in corso, processamento documenti automatico"
        }
      rescue StandardError => e
        cleanup_failed_source_file(source_path)
        raise e
      end

      private

      def compute_checksum(file)
        io = file.respond_to?(:tempfile) ? file.tempfile : file
        io.rewind if io.respond_to?(:rewind)
        data = io.read
        io.rewind if io.respond_to?(:rewind)
        Digest::SHA256.hexdigest(data)
      end

      private

      attr_reader :upload_manager, :pdf_split_job_class, :pdf_loader, :file_storage

      def cleanup_failed_source_file(path)
        return unless path.present? && file_storage.exist?(path)

        file_storage.delete(path)
      end
    end
  end
end