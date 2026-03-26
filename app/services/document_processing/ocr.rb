module DocumentProcessing
  class Ocr
    def initialize(textract_client:)
      @textract = textract_client
    end

    def page_texts_with_layout(pdf)
      pdf.pages.map { |page| layout_text(page) }
    end

    def quick_ocr(page)
      tmp_pdf = CombinePDF.new << page
      extract_line_blocks(document_bytes: tmp_pdf.to_pdf).map(&:text).join("\n")
    end

    def full_ocr(file_path)
      pdf = CombinePDF.load(file_path)
      line_items = pdf.pages.flat_map { |page| extract_line_items(page) }

      {
        text: line_items.map { |line| line[:text] }.join("\n"),
        lines: line_items
      }
    end

    private

    def layout_text(page)
      tmp_pdf = CombinePDF.new << page
      response = @textract.analyze_document(
        document: { bytes: tmp_pdf.to_pdf },
        feature_types: ["LAYOUT"]
      )

      extract_layout_blocks(response.blocks)
    rescue StandardError => error
      Rails.logger.warn("Textract layout fallback su detect_document_text: #{error.message}")
      quick_ocr(page)
    end

    def extract_line_items(page)
      tmp_pdf = CombinePDF.new << page

      extract_line_blocks(document_bytes: tmp_pdf.to_pdf).map do |block|
        {
          text: block.text.to_s,
          confidence: block.respond_to?(:confidence) ? block.confidence.to_f : nil
        }
      end
    end

    def extract_line_blocks(document_bytes:)
      response = @textract.detect_document_text(document: { bytes: document_bytes })
      response.blocks.select { |block| block.block_type == "LINE" }
    end

    def extract_layout_blocks(blocks)
      return "" if blocks.blank?

      blocks
        .select { |block| block.respond_to?(:text) && block.text.present? }
        .select { |block| block.block_type == "LINE" || block.block_type.to_s.start_with?("LAYOUT_") }
        .map(&:text)
        .join("\n")
    end
  end
end
