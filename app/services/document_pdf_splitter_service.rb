# === DocumentPdfSplitterService ===
# Divide un PDF multi-documento in mini-PDF singoli.
#
# Strategia:
#   1. Estrae le prime righe di ogni pagina (leggero, via Textract)
#   2. Manda un riassunto al LLM (Nova Lite) con UNA sola chiamata:
#      "Quali pagine sono l'inizio di un nuovo documento?"
#
# Il LLM capisce la semantica: gestisce lunghezze variabili,
# documenti identici e strutture miste.
#
# Esempio:
#   Input: cedolini.pdf (20 pagine, 5 cedolini da 4 pagine ciascuno)
#   Output: [tmp_split_0_xxx.pdf, tmp_split_1_xxx.pdf, ...]
#
class DocumentPdfSplitterService
  # Quante righe per pagina mandare al LLM (abbastanza per capire il tipo)
  PREVIEW_LINES = 8

  def initialize(pdf:, ocr_service:, llm_service: nil, bedrock_client: Aws::BedrockRuntime::Client.new)
    @pdf = pdf
    @ocr_service = ocr_service
    @llm_service = llm_service || DocumentProcessing::LlmService.new(bedrock_client: bedrock_client)
  end

  # Ritorna array di hash con range e percorso del mini-PDF creato
  def split
    ranges = identify_ranges
    Rails.logger.info "[Splitter] Split chiamato, ranges calcolati: #{ranges.inspect}"
    
    mini_pdfs = ranges.each_with_index.map do |range, index|
      Rails.logger.info "[Splitter] Creando mini-PDF ##{index}: pagine #{range[:start]}→#{range[:end]}"
      {
        range:,
        path: create_mini_pdf(range:, index:)
      }
    end
    
    Rails.logger.info "[Splitter] Split completato: #{mini_pdfs.size} file creati"
    mini_pdfs
  end

  private

  attr_reader :pdf, :ocr_service, :llm_service

  # ─── ORCHESTRAZIONE ────────────────────────────────────────────────

  # Identifica i breakpoint (inizi nuovi documenti) nel PDF
  def identify_ranges
    page_texts = ocr_service.page_texts_with_layout(pdf)
    return [{ start: 0, end: pdf.pages.size - 1 }] if page_texts.blank?

    Rails.logger.info "[Splitter] Chiedendo al LLM di identificare i breakpoint..."
    breakpoints = detect_breakpoints_via_llm(page_texts)
    Rails.logger.info "[Splitter] LLM riuscito, breakpoints trovati: #{breakpoints.inspect}"

    # Se nessun breakpoint trovato, ritorna il PDF intero
    if breakpoints.empty?
      Rails.logger.info "[Splitter] Nessun breakpoint trovato → documento singolo"
      return [{ start: 0, end: pdf.pages.size - 1 }]
    end

    breakpoints.unshift(0) if breakpoints.first != 0

    ranges = breakpoints_to_ranges(breakpoints)
    Rails.logger.info "[Splitter] Ranges finali: #{ranges.inspect}"
    ranges
  end

  # Converte breakpoint [0, 3, 7] → ranges [{start:0, end:2}, {start:3, end:6}, ...]
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

  # ─── STRATEGIA 1: LLM ─────────────────────────────────────────────

  # Manda un riassunto di ogni pagina al LLM e chiede:
  # "Quali pagine iniziano un nuovo documento?"
  # Una sola chiamata API, gestisce qualsiasi struttura.
  def detect_breakpoints_via_llm(page_texts)
    summary = build_page_summary(page_texts)
    Rails.logger.info "[Splitter LLM] Summary completo inviato (#{page_texts.size} pagine):\n#{summary}"

    json = llm_service.detect_split_breakpoints(summary)
    Rails.logger.info "[Splitter LLM] JSON parsato: #{json.inspect}"
    
    pages = Array(json["start_pages"]).map(&:to_i).uniq.sort
    valid_pages = pages.select { |p| p >= 0 && p < page_texts.length }
    
    Rails.logger.info "[Splitter LLM] Pagine valide dopo filtro: #{valid_pages.inspect}"
    valid_pages
  rescue StandardError => error
    Rails.logger.error("[Splitter LLM] ERRORE: #{error.class} - #{error.message}")
    Rails.logger.debug(error.backtrace.first(3).join("\n"))
    raise
  end

  # Costruisce un riassunto compatto: prime PREVIEW_LINES righe di ogni pagina
  def build_page_summary(page_texts)
    page_texts.each_with_index.map do |text, index|
      lines = text.to_s.lines.map(&:strip).reject(&:blank?).first(PREVIEW_LINES)
      preview = lines.join(" | ")
      "PAGINA #{index}: #{preview}"
    end.join("\n")
  end

  # Crea un mini-PDF dalle pagine nel range e lo salva in tmp/
  def create_mini_pdf(range:, index:)
    new_pdf = CombinePDF.new
    (range[:start]..range[:end]).each { |page_index| new_pdf << pdf.pages[page_index] }

    filename = "tmp_split_#{index}_#{Time.current.to_i}.pdf"
    path = Rails.root.join("tmp", filename)
    new_pdf.save(path.to_s)
    path.to_s
  end
end
