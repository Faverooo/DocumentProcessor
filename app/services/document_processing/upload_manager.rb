require "fileutils"
require "digest"

module DocumentProcessing
  class UploadManager
    MAX_PDF_SIZE = 50.megabytes
    MAX_GENERIC_SIZE = 20.megabytes
    ALLOWED_PDF_CONTENT_TYPES = [
      "application/pdf",
      "application/x-pdf",
      "application/acrobat",
      "applications/vnd.pdf",
      "text/pdf",
      "text/x-pdf",
      "application/octet-stream"
    ].freeze

    ALLOWED_CSV_CONTENT_TYPES = [
      "text/csv",
      "application/csv",
      "application/vnd.ms-excel"
    ].freeze

    ALLOWED_IMAGE_CONTENT_TYPES = [
      "image/jpeg",
      "image/jpg",
      "image/png"
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

    def persist_supported_source_file(file)
      kind = detect_upload_kind(file)
      validate_supported_upload!(file, kind)
      save_file(file:, base_dir: Rails.root.join("storage", "uploads", "source_documents"), random_bytes: 8)
    end

    def detect_upload_kind(file)
      return :unknown unless file.present?

      filename = file.original_filename.to_s.downcase
      content_type = file.content_type.to_s.downcase

      return :pdf if filename.end_with?(".pdf") || ALLOWED_PDF_CONTENT_TYPES.include?(content_type)
      return :csv if filename.end_with?(".csv") || ALLOWED_CSV_CONTENT_TYPES.include?(content_type)
      return :image if %w[.jpg .jpeg .png].any? { |ext| filename.end_with?(ext) } || ALLOWED_IMAGE_CONTENT_TYPES.include?(content_type)

      :unknown
    end

    def compute_checksum(file)
      io = file.respond_to?(:tempfile) ? file.tempfile : file
      io.rewind if io.respond_to?(:rewind)
      data = io.read
      io.rewind if io.respond_to?(:rewind)
      Digest::SHA256.hexdigest(data)
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

    def validate_supported_upload!(file, kind)
      raise ValidationError, "Nessun file selezionato" unless file.present?
      raise ValidationError, "Formato non supportato" if kind == :unknown
      raise ValidationError, "File troppo grande (max 20 MB)" if file_size(file) > MAX_GENERIC_SIZE

      content_type = file.content_type.to_s.downcase

      case kind
      when :csv
        valid_ext = file.original_filename.to_s.downcase.end_with?(".csv")
        valid_type = ALLOWED_CSV_CONTENT_TYPES.include?(content_type)
        raise ValidationError, "Formato non valido: carica un CSV" unless valid_ext || valid_type
      when :image
        valid_ext = %w[.jpg .jpeg .png].any? { |ext| file.original_filename.to_s.downcase.end_with?(ext) }
        valid_type = ALLOWED_IMAGE_CONTENT_TYPES.include?(content_type)
        raise ValidationError, "Formato non valido: carica un JPEG o PNG" unless valid_ext || valid_type
      when :pdf
        validate_pdf_upload!(file)
      else
        raise ValidationError, "Formato non supportato"
      end
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
      sanitized = "upload.bin" if sanitized.blank?
      sanitized
    end
  end
end