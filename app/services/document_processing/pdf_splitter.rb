module DocumentProcessing
  class PdfSplitter
    PREVIEW_LINES = 8

    def initialize(pdf:, ocr_service:, llm_service:)
      @pdf = pdf
      @ocr_service = ocr_service
      @llm_service = llm_service
    end

    def split
      ranges = identify_ranges

      ranges.each_with_index.map do |range, index|
        {
          range: range,
          path: create_mini_pdf(range: range, index: index)
        }
      end
    end

    private

    attr_reader :pdf, :ocr_service, :llm_service

    def identify_ranges
      page_texts = ocr_service.page_texts_with_layout(pdf)
      return [{ start: 0, end: pdf.pages.size - 1 }] if page_texts.blank?

      breakpoints = detect_breakpoints_via_llm(page_texts)
      return [{ start: 0, end: pdf.pages.size - 1 }] if breakpoints.empty?

      breakpoints.unshift(0) if breakpoints.first != 0
      breakpoints_to_ranges(breakpoints)
    end

    def breakpoints_to_ranges(breakpoints)
      breakpoints.each_with_index.map do |start_index, idx|
        end_index = if idx == breakpoints.length - 1
          pdf.pages.size - 1
        else
          breakpoints[idx + 1] - 1
        end
        { start: start_index, end: end_index }
      end
    end

    def detect_breakpoints_via_llm(page_texts)
      summary = build_page_summary(page_texts)
      json = llm_service.detect_split_breakpoints(summary)

      pages = Array(json["start_pages"]).map(&:to_i).uniq.sort
      pages.select { |p| p >= 0 && p < page_texts.length }
    rescue StandardError
      raise
    end

    def build_page_summary(page_texts)
      page_texts.each_with_index.map do |text, index|
        lines = text.to_s.lines.map(&:strip).reject(&:blank?).first(PREVIEW_LINES)
        preview = lines.join(" | ")
        "PAGINA #{index}: #{preview}"
      end.join("\n")
    end

    def create_mini_pdf(range:, index:)
      new_pdf = CombinePDF.new
      (range[:start]..range[:end]).each { |page_index| new_pdf << pdf.pages[page_index] }

      filename = "tmp_split_#{index}_#{Time.current.to_i}.pdf"
      path = Rails.root.join("tmp", filename)
      new_pdf.save(path.to_s)
      path.to_s
    end
  end
end
