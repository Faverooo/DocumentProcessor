require "fileutils"

module DocumentProcessing
  class UploadManager
    MAX_PDF_SIZE = 50.megabytes
    ALLOWED_PDF_CONTENT_TYPES = [
      "application/pdf",
      "application/x-pdf",
      "application/acrobat",
      "applications/vnd.pdf",
      "text/pdf",
      "text/x-pdf",
      "application/octet-stream"
    ].freeze

    class ValidationError < StandardError; end
    class PersistenceError < StandardError; end

    def persist_temp_pdf(file)
      validate_pdf_upload!(file)
      save_file(file:, base_dir: Rails.root.join("tmp", "uploads"), random_bytes: 6)
    end

    def persist_source_pdf(file)
      validate_pdf_upload!(file)
      save_file(file:, base_dir: Rails.root.join("storage", "uploads", "source_documents"), random_bytes: 8)
    end

    private

    def save_file(file:, base_dir:, random_bytes:)
      FileUtils.mkdir_p(base_dir)

      safe_name = sanitized_original_filename(file.original_filename)
      path = base_dir.join("#{Time.current.to_i}_#{SecureRandom.hex(random_bytes)}_#{safe_name}")

      rewind_if_possible(file)
      File.binwrite(path, file.read)
      path.to_s
    rescue StandardError => e
      raise PersistenceError, e.message
    end

    def validate_pdf_upload!(file)
      raise ValidationError, "Nessun file selezionato" unless file.present?
      raise ValidationError, "Il file deve avere estensione .pdf" unless file.original_filename.to_s.downcase.end_with?(".pdf")
      raise ValidationError, "File troppo grande (max 50 MB)" if file_size(file) > MAX_PDF_SIZE

      content_type = file.content_type.to_s.downcase
      raise ValidationError, "Formato non valido: carica un PDF" unless ALLOWED_PDF_CONTENT_TYPES.include?(content_type)
      raise ValidationError, "Contenuto file non valido: il file non sembra un PDF" unless pdf_signature_valid?(file)
    end

    def file_size(file)
      return file.size.to_i if file.respond_to?(:size)
      return file.tempfile.size.to_i if file.respond_to?(:tempfile) && file.tempfile.respond_to?(:size)

      0
    end

    def pdf_signature_valid?(file)
      io = file.respond_to?(:tempfile) ? file.tempfile : file
      return false unless io.respond_to?(:read)

      io.rewind if io.respond_to?(:rewind)
      signature = io.read(5)
      io.rewind if io.respond_to?(:rewind)
      signature == "%PDF-"
    rescue StandardError
      false
    end

    def rewind_if_possible(file)
      file.tempfile.rewind if file.respond_to?(:tempfile) && file.tempfile.respond_to?(:rewind)
      file.rewind if file.respond_to?(:rewind)
    end

    def sanitized_original_filename(name)
      basename = File.basename(name.to_s)
      sanitized = basename.gsub(/[^0-9A-Za-z.\-_]/, "_")
      sanitized = "upload.pdf" if sanitized.blank?
      sanitized = "#{sanitized}.pdf" unless sanitized.downcase.end_with?(".pdf")
      sanitized
    end
  end
end