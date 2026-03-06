# === DocumentPdfSplitterService ===
# Divide un PDF multi-documento in mini-PDF singoli.
#
# Strategia ibrida:
#   1. Estrae le prime righe di ogni pagina (leggero, via Textract)
#   2. Manda un riassunto al LLM (Nova Lite) con UNA sola chiamata:
#      "Quali pagine sono l'inizio di un nuovo documento?"
#   3. Se il LLM fallisce → fallback algoritmico (fingerprint + Jaccard)
#
# Il LLM capisce la semantica: gestisce lunghezze variabili,
# documenti identici, strutture miste. L'algoritmo no.
#
# Esempio:
#   Input: cedolini.pdf (20 pagine, 5 cedolini da 4 pagine ciascuno)
#   Output: [tmp_split_0_xxx.pdf, tmp_split_1_xxx.pdf, ...]
#
class DocumentPdfSplitterService
  # Quante righe per pagina mandare al LLM (abbastanza per capire il tipo)
  PREVIEW_LINES = 8
  # Soglie per fallback algoritmico
  RECURRENCE_SIMILARITY_MIN = 0.42
  TRANSITION_SIMILARITY_MAX = 0.28
  TOKEN_WINDOW_SIZE = 70

  def initialize(pdf:, ocr_service:, bedrock_client: Aws::BedrockRuntime::Client.new)
    @pdf = pdf
    @ocr_service = ocr_service
    @bedrock = bedrock_client
  end

  # Ritorna array di percorsi ai mini-PDF creati
  def split
    ranges = identify_ranges
    Rails.logger.info "[Splitter] Split chiamato, ranges calcolati: #{ranges.inspect}"
    
    mini_pdfs = ranges.each_with_index.map do |range, index|
      Rails.logger.info "[Splitter] Creando mini-PDF ##{index}: pagine #{range[:start]}→#{range[:end]}"
      create_mini_pdf(range:, index:)
    end
    
    Rails.logger.info "[Splitter] Split completato: #{mini_pdfs.size} file creati"
    mini_pdfs
  end

  private

  attr_reader :pdf, :ocr_service, :bedrock

  # ─── ORCHESTRAZIONE ────────────────────────────────────────────────

  # Identifica i breakpoint (inizi nuovi documenti) nel PDF
  def identify_ranges
    page_texts = ocr_service.page_texts_with_layout(pdf)
    return [{ start: 0, end: pdf.pages.size - 1 }] if page_texts.blank?

    # Prima prova con il LLM (più accurato)
    Rails.logger.info "[Splitter] Chiedendo al LLM di identificare i breakpoint..."
    breakpoints, llm_succeeded = detect_breakpoints_via_llm(page_texts)
    
    if llm_succeeded
      Rails.logger.info "[Splitter] LLM riuscito, breakpoints trovati: #{breakpoints.inspect}"
    else
      Rails.logger.warn "[Splitter] LLM fallito, uso fallback algoritmico"
    end

    # Fallback algoritmico SOLO se il LLM ha fallito (non se ha detto "è un solo documento")
    unless llm_succeeded
      breakpoints = detect_breakpoints_via_algorithm(page_texts)
      Rails.logger.info "[Splitter] Algoritmo ha trovato breakpoints: #{breakpoints.inspect}"
    end

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
  # Ritorna [breakpoints, success_flag].
  def detect_breakpoints_via_llm(page_texts)
    summary = build_page_summary(page_texts)
    Rails.logger.info "[Splitter LLM] Summary completo inviato (#{page_texts.size} pagine):\n#{summary}"

    response = bedrock.invoke_model(
      model_id: ENV.fetch("BEDROCK_MODEL_ID", "amazon.nova-lite-v1:0"),
      body: split_request_body(summary),
      content_type: "application/json",
      accept: "application/json"
    )

    # Formato risposta Amazon Nova: output.message.content[0].text
    parsed = JSON.parse(response.body.read)
    content = parsed.dig("output", "message", "content", 0, "text").to_s
    Rails.logger.debug "[Splitter LLM] Risposta raw: #{content}"

    # Estrai JSON dalla risposta anche se il LLM aggiunge testo introduttivo
    # Cerca il primo oggetto JSON { ... } nella risposta
    json_match = content.match(/\{.*\}/m)
    raise "Nessun JSON trovato nella risposta LLM" unless json_match

    json = JSON.parse(json_match[0])
    Rails.logger.info "[Splitter LLM] JSON parsato: #{json.inspect}"
    
    pages = Array(json["start_pages"]).map(&:to_i).uniq.sort
    valid_pages = pages.select { |p| p >= 0 && p < page_texts.length }
    
    Rails.logger.info "[Splitter LLM] Pagine valide dopo filtro: #{valid_pages.inspect}"
    [valid_pages, true]  # [breakpoints, succeeded]
  rescue StandardError => error
    Rails.logger.error("[Splitter LLM] ERRORE: #{error.class} - #{error.message}")
    Rails.logger.debug(error.backtrace.first(3).join("\n"))
    [[0], false]  # [breakpoints, succeeded=false]
  end

  # Costruisce un riassunto compatto: prime PREVIEW_LINES righe di ogni pagina
  def build_page_summary(page_texts)
    page_texts.each_with_index.map do |text, index|
      lines = text.to_s.lines.map(&:strip).reject(&:blank?).first(PREVIEW_LINES)
      preview = lines.join(" | ")
      "PAGINA #{index}: #{preview}"
    end.join("\n")
  end

  # Body della richiesta Bedrock per Amazon Nova Lite
  # Formato Nova: messages con content array, inferenceConfig separato (diverso da Claude)
  def split_request_body(summary)
    {
      messages: [
        { role: "user", content: [{ text: split_prompt(summary) }] }
      ],
      inferenceConfig: {
        maxTokens: 500,
        temperature: 0.0
      }
    }.to_json
  end

  # Prompt per il LLM: identifica dove iniziano nuovi documenti
  def split_prompt(summary)
    <<~PROMPT
      Sei un sistema di analisi documentale. Il tuo compito è identificare dove inizia ogni nuovo documento
      all'interno di un PDF che può contenere più documenti uniti (cedolini, fatture, contratti, lettere o altro).

      CRITERI DI IDENTIFICAZIONE:
      1. Cambio di destinatario (nome, matricola, codice fiscale diversi)
      2. Intestazioni identiche ripetute (segnale di nuovo documento dello stesso tipo)
      3. Cambio di struttura o layout
      4. Numerazione che ricomincia (es. "Pag 1/3" dopo "Pag 3/3")

      REGOLE FONDAMENTALI:
      - La PAGINA 0 è SEMPRE l'inizio del primo documento
      - Documenti dello stesso tipo per persone diverse sono documenti SEPARATI
      - Un documento può essere lungo 1 o più pagine consecutive
      - Usa ESATTAMENTE gli indici numerici mostrati (PAGINA 0 → 0, PAGINA 1 → 1, PAGINA 2 → 2, etc.)

      ESEMPI:
      
      Caso 1 - Tre cedolini singoli per dipendenti diversi:
      PAGINA 0: Cedolino - Dipendente: Mario Rossi
      PAGINA 1: Cedolino - Dipendente: Anna Bianchi  
      PAGINA 2: Cedolino - Dipendente: Luca Verdi
      → Risposta: {"start_pages": [0, 1, 2]}

      Caso 2 - Due fatture multi-pagina:
      PAGINA 0: Fattura 001 - Cliente ABC (Pag 1/2)
      PAGINA 1: Fattura 001 - Cliente ABC (Pag 2/2)
      PAGINA 2: Fattura 002 - Cliente XYZ (Pag 1/1)
      → Risposta: {"start_pages": [0, 2]}

      Caso 3 - Documento unico:
      PAGINA 0: Contratto (Pag 1/5)
      PAGINA 1: Contratto (Pag 2/5)
      → Risposta: {"start_pages": [0]}

      FORMATO OUTPUT:
      Rispondi SOLO con un oggetto JSON valido contenente l'array "start_pages".
      Ad esempio: {"start_pages": [0, 3, 7]}

      ═══════════════════════════════════════════════════════════
      ANTEPRIME PAGINE:
      #{summary}
      ══════════════════════════════════════════════════════
    PROMPT
  end

  # ─── STRATEGIA 2: FALLBACK ALGORITMICO ─────────────────────────────

  # Fallback se il LLM non è disponibile o fallisce.
  # Usa fingerprint + Jaccard similarity.
  def detect_breakpoints_via_algorithm(page_texts)
    fingerprints = page_texts.map { |text| page_fingerprint(text) }

    # Prova ricerca transizionale
    trans_starts = search_by_transition(fingerprints)

    # Prova ricerca per intervallo
    interval_starts = search_by_interval(fingerprints)

    # Scegli quella che trova più breakpoint (più granulare)
    if interval_starts.length > trans_starts.length
      interval_starts
    else
      trans_starts
    end
  end

  # Ricerca transizionale: pagine diverse dalla precedente e simili ad altre lontane
  def search_by_transition(fingerprints)
    starts = [0]

    (1...fingerprints.size).each do |index|
      current = fingerprints[index]
      previous = fingerprints[index - 1]
      next if current.empty?

      recurrence = max_recurrence_similarity(current, fingerprints, index)
      transition = jaccard_similarity(current, previous)

      if recurrence >= RECURRENCE_SIMILARITY_MIN && transition <= TRANSITION_SIMILARITY_MAX
        starts << index
      end
    end

    starts.uniq.sort
  end

  # Ricerca per intervallo: rileva il periodo ricorrente (ogni N pagine)
  def search_by_interval(fingerprints)
    return [0] if fingerprints.length <= 1

    similarities_by_interval = {}
    (0...fingerprints.length).each do |i|
      (i + 1...fingerprints.length).each do |j|
        sim = jaccard_similarity(fingerprints[i], fingerprints[j])
        interval = j - i
        similarities_by_interval[interval] ||= []
        similarities_by_interval[interval] << sim
      end
    end

    best_interval = nil
    best_avg = 0
    similarities_by_interval.each do |interval, sims|
      avg = sims.sum.to_f / sims.length
      if avg >= RECURRENCE_SIMILARITY_MIN && avg > best_avg
        best_interval = interval
        best_avg = avg
      end
    end

    return [0] unless best_interval

    starts = [0]
    (best_interval...fingerprints.length).step(best_interval) do |idx|
      starts << idx if idx < fingerprints.length
    end

    starts.uniq.sort
  end

  # ─── UTILITÀ ───────────────────────────────────────────────────────

  def max_recurrence_similarity(current_fp, all_fps, current_idx)
    sims = all_fps.each_with_index.filter_map do |candidate, idx|
      next if idx == current_idx || (idx - current_idx).abs <= 1 || candidate.empty?
      jaccard_similarity(current_fp, candidate)
    end
    sims.max.to_f
  end

  def page_fingerprint(text)
    normalized = normalize_text(text)
    return [] if normalized.blank?

    tokens = normalized.split.first(TOKEN_WINDOW_SIZE)
    tokens.reject! { |t| t.match?(/\A\d+\z/) || t.length < 3 }
    return tokens.uniq if tokens.length < 2

    tokens.each_cons(2).map { |a, b| "#{a}_#{b}" }.uniq
  end

  def jaccard_similarity(left, right)
    l = Array(left).uniq
    r = Array(right).uniq
    return 0.0 if l.empty? || r.empty?

    intersection = (l & r).size.to_f
    union = (l | r).size.to_f
    union.zero? ? 0.0 : intersection / union
  end

  def normalize_text(text)
    text.to_s.downcase.gsub(/[^\p{Alnum}\s]/, " ").gsub(/\s+/, " ").strip
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
