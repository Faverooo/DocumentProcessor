require "fileutils"

module DocumentProcessing
  class PageRangePdf
    def initialize(source_pdf_path:)
      @source_pdf_path = source_pdf_path
    end

    def build_temp_pdf(page_start:, page_end:)
      pdf = CombinePDF.load(source_pdf_path)
      validate_range!(pdf: pdf, page_start: page_start, page_end: page_end)

      selected_pdf = CombinePDF.new
      ((page_start - 1)..(page_end - 1)).each do |zero_based_index|
        selected_pdf << pdf.pages[zero_based_index]
      end

      temp_dir = Rails.root.join("tmp", "extracted")
      FileUtils.mkdir_p(temp_dir)

      file_path = temp_dir.join("range_#{SecureRandom.hex(8)}.pdf")
      selected_pdf.save(file_path.to_s)
      file_path.to_s
    end

    private

    attr_reader :source_pdf_path

    def validate_range!(pdf:, page_start:, page_end:)
      raise ArgumentError, "Range pagine non valido" unless page_start.is_a?(Integer) && page_end.is_a?(Integer)
      raise ArgumentError, "Range pagine non valido" if page_start <= 0 || page_end <= 0
      raise ArgumentError, "Range pagine non valido" if page_end < page_start
      raise ArgumentError, "Range oltre il numero di pagine disponibili" if page_end > pdf.pages.size
    end
  end
end
