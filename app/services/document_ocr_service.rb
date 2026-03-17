# === DocumentOcrService ===
# Servizio di estrazione testo via AWS Textract.
# 
# Due modalità:
#   - page_texts_with_layout: Usa LAYOUT per identificare struttura (per splitting)
#   - full_ocr: OCR completo su singolo documento
#
class DocumentOcrService
  def initialize(textract_client: Aws::Textract::Client.new)
    @textract = textract_client  # Client AWS Textract
  end

  # Estrae testo con analisi LAYOUT da ogni pagina (usato per identificare split)
  def page_texts_with_layout(pdf)
    pdf.pages.map { |page| layout_text(page) }
  end

  # OCR veloce su una singola pagina (per trovare breakpoint di split)
  # Usato come fallback se LAYOUT non è disponibile o fallisce
  def quick_ocr(page)
    tmp_pdf = CombinePDF.new << page
    extract_line_blocks(document_bytes: tmp_pdf.to_pdf).map(&:text).join("\n")
  end

  # OCR completo su un file intero (per estrazione destinatari)
  # Ritorna { text: String, lines: [{ text:, confidence: }] }
  # Processa pagina per pagina perché Textract non supporta PDF multi-pagina in modalità sincrona
  def full_ocr(file_path)
    pdf = CombinePDF.load(file_path)
    line_items = pdf.pages.flat_map { |page| extract_line_items(page) }

    {
      text: line_items.map { |line| line[:text] }.join("\n"),
      lines: line_items
    }
  end

  private

  # Usa Textract ANALYZE_DOCUMENT con feature LAYOUT per capire la struttura della pagina
  # Fallback a quick_ocr se la feature non è disponibile
  def layout_text(page)
    tmp_pdf = CombinePDF.new << page
    response = @textract.analyze_document(
      document: { bytes: tmp_pdf.to_pdf },
      feature_types: ["LAYOUT"]  # Analizza layout (titoli, intestazioni...)
    )

    extract_layout_blocks(response.blocks)
  rescue StandardError => error
    # Se layout fallisce, retrocedi a OCR semplice
    Rails.logger.warn("Textract layout fallback su detect_document_text: #{error.message}")
    quick_ocr(page)
  end

  def extract_line_items(page) # simile a extract_lines ma ritorna array di hash con testo e confidence
    tmp_pdf = CombinePDF.new << page

    extract_line_blocks(document_bytes: tmp_pdf.to_pdf).map do |block|
      {
        text: block.text.to_s,
        confidence: block.respond_to?(:confidence) ? block.confidence.to_f : nil
      }
    end
  end

  def extract_line_blocks(document_bytes:) # converte i blocchi LINE di una pagina in una lista di hash
    response = @textract.detect_document_text(document: { bytes: document_bytes })
    response.blocks.select { |block| block.block_type == "LINE" }
  end

  # Estrae blocchi LAYOUT primari (titoli, sezioni...)
  def extract_layout_blocks(blocks)
    return "" if blocks.blank?

    #prende i blocchi Textract, tiene solo quelli con testo rilevante
    #(righe e layout strutturali), estrae il contenuto testuale e lo concatena in una singola stringa con newline.
    blocks
      .select { |block| block.respond_to?(:text) && block.text.present? }
      .select { |block| block.block_type == "LINE" || block.block_type.to_s.start_with?("LAYOUT_") }
      .map(&:text)
      .join("\n")  # Newline per preservare la struttura riga per riga
  end
end
