# === DocumentRecipientResolverService ===
# Matcha i nomi estratti (via LLM) con i dipendenti aziendali nel DB.
#
# Logica:
#   1. Ricevi nome estratto dal LLM (es. "Mario Rossi")
#   2. Normalizza (lowercase, no accenti)
#   3. Cerca candidati simili nel DB (via SQL LIKE + filtro email)
#   4. Calcola similarità con 3 metriche:
#      - Exact/near-exact match (1.0 / 0.95) — token-set, fast path
#      - Fuzzy token score (Jaro-Winkler) — gestisce typo OCR e varianti ortografiche
#      - Dice coefficient a livello bigrammi — rinforza similarità carattere/posizione
#   5. Applica penalità per query molto lunghe (raw_text) per ridurre falsi positivi
#   6. Ritorna Employee se score >= threshold (default 0.72),
#      altrimenti ritorna il testo grezzo originale (mai nil)
#
class DocumentRecipientResolverService
  DEFAULT_THRESHOLD = 0.72  # Soglia di similarità (0-1)

  def initialize(threshold: DEFAULT_THRESHOLD)
    @threshold = threshold
  end

  # Matcha i nomi estratti contro il DB
  # recipient_names: ["Mario Rossi", ...] da LLM
  # raw_text: fallback se recipient_names è vuoto
  # Ritorna: Employee object se il match supera la soglia,
  #          String (testo grezzo) se nessun candidato combacia,
  #          nil solo se non c'è alcun testo da matchare
  def resolve(recipient_names:, raw_text: nil)
    names = Array(recipient_names).reject(&:blank?)

    # Testo grezzo da restituire in caso di mancato match (mai normalizzato)
    fallback_text = names.first.presence || raw_text

    # Normalizza i nomi estratti dal LLM
    search_terms = names.map { |name| normalize(name) }.reject(&:blank?)

    # Se nessun nome estratto, usa il testo grezzo come fallback di ricerca
    if search_terms.empty? && raw_text.present?
      search_terms = [normalize(raw_text)]
    end
    return nil if search_terms.empty?

    # Matcha ogni termine di ricerca e prendi il best match
    best_match = search_terms
      .flat_map { |term| best_matches_for_term(term) }  # Genera candidati
      .max_by { |candidate| candidate[:score] }        # Prendi il migliore

    if best_match && best_match[:score] >= @threshold
      best_match[:employee]   # Match trovato → ritorna l'oggetto Employee
    else
      fallback_text           # Nessun match → ritorna il testo grezzo originale
    end
  end

  private

  # Calcola i migliori match per un singolo termine
  def best_matches_for_term(normalized_term)
    candidate_employees(normalized_term)  # Prendi candidati dal DB
      .map { |employee| score_candidate(employee, normalized_term) }  # Calcola score
      .compact  # Rimuovi nil
  end

  # Cerca dipendenti simili nel DB (pre-filtering via SQL per performanza)
  # - Estrae token dal nome (es. "mario rossi" → ["mario", "rossi"])
  # - Usa WHERE LIKE %token% per ridurre candidati
  # - Considera solo employee con email (nota: puoi aggiungere fallback senza email)
  def candidate_employees(normalized_term)
    tokens = normalized_term.split.uniq.select { |token| token.length >= 3 }.first(8)
    scope = Employee.select(:id, :name, :email, :employee_code).where.not(email: [nil, ""])

    if tokens.any?
      where_clause = tokens.map { "LOWER(name) LIKE ?" }.join(" OR ")
      like_values = tokens.map { |token| "%#{token}%" }
      scoped = scope.where(where_clause, *like_values).limit(300).to_a
      return scoped if scoped.any?
    end

    scope.limit(500).to_a
  end

  # Calcola il score di similarità tra un Employee e il termine ricercato.
  # Usa 3 metriche combinate:
  #   1. Exact/near-exact match  → 1.0 se identici, 0.95 se token-set contenimento (fast path)
  #   2. Fuzzy token score (JW)  → Jaro-Winkler per token, precision-oriented:
  #                                  - gestisce typo OCR ("maria"→"mario")
  #                                  - non penalizza token extra nel nome DB (titoli, suffissi)
  #                                  - copre già i match esatti (JW=1.0 se token identici)
  #   3. Dice coefficient        → bigrammi, complementa JW per trasposizioni di caratteri
  #                                  e variazioni ortografiche indipendenti dalla posizione
  #
  # NOTA: token_overlap (Dice a parole) è stato rimosso perché:
  #   - ridondante: JW copre già i match esatti
  #   - dannoso: penalizza nomi DB con titoli ("dott mario rossi" → Dice 0.80 invece di 1.0)
  def score_candidate(employee, normalized_term)
    normalized_name = normalize(employee.name)
    return nil if normalized_name.blank?

    name_tokens = normalized_name.split.uniq
    term_tokens = normalized_term.split.uniq

    # Metrica 1: exact / near-exact (solo per termini brevi, max 6 token)
    # Usa confronto per token-set, NON String#include? (che è substring e causa falsi positivi:
    # es. "rossi" matcha dentro "rossini" con include?, ma NON con token-set)
    exact_score = if term_tokens.size <= 6
      if normalized_name == normalized_term
        1.0  # Identici
      elsif (term_tokens - name_tokens).empty? || (name_tokens - term_tokens).empty?
        0.95  # Tutti i token di uno sono contenuti nell'altro (es. "Mario Rossi" ⊆ "Dott. Mario Rossi")
      else
        0.0
      end
    else
      0.0
    end

    # Metrica 2: fuzzy token score via Jaro-Winkler
    # Per ogni token della query trova il token più simile nel nome DB (best match).
    # Gestisce typo OCR ("maria"→"mario"), lettere scambiate, varianti ortografiche.
    jw_score = fuzzy_token_score(term_tokens, name_tokens)

    # Metrica 3: Dice coefficient a livello bigrammi
    # Rinforza JW per trasposizioni e variazioni di carattere indipendenti dalla posizione.
    char_score = dice_coefficient(normalized_name, normalized_term)

    # Penalità progressiva per query molto lunghe (riduce falsi positivi con raw_text)
    # Inizia a penalizzare oltre 8 token, non scende mai sotto 0.5
    length_penalty = if term_tokens.size > 8
      [1.0 - ((term_tokens.size - 8) * 0.05), 0.5].max
    else
      1.0
    end

    # Score finale: massimo tra exact e combinazione pesata JW + Dice
    combined = (jw_score * 0.60 + char_score * 0.40) * length_penalty
    final_score = [exact_score, combined].max

    { employee:, score: final_score }
  end

  # Normalizza un nome: decompone accenti Unicode, lowercase, rimuove punteggiatura
  # Esempio: "Müller" → "muller", "Éric Rossi" → "eric rossi"
  def normalize(value)
    value.to_s
      .unicode_normalize(:nfd)  # Decomponi caratteri accentati (é → e + ́)
      .gsub(/\p{Mn}/, "")       # Rimuovi i diacritici (combining marks)
      .downcase
      .gsub(/[^a-z0-9\s]/, " ") # Sostituisci punteggiatura con spazi
      .gsub(/\s+/, " ")          # Rimuovi spazi multipli
      .strip
  end

  # Fuzzy token score via Jaro-Winkler:
  # Per ogni token della query, trova il token più simile nel nome candidato (best JW match).
  # Ritorna la media di questi best-match: se tutti i token matchano bene → score vicino a 1.0
  #
  # Esempi:
  #   ["maria", "rossi"] vs ["mario", "rosso"]  → (JW(maria,mario) + JW(rossi,rosso)) / 2
  #                                               → (0.92 + 0.93) / 2 ≈ 0.93  ✓ sopra soglia
  #   ["luigi", "bianchi"] vs ["mario", "rosso"] → (0.51 + 0.44) / 2 ≈ 0.47  ✗ sotto soglia
  def fuzzy_token_score(term_tokens, name_tokens)
    return 0.0 if term_tokens.empty? || name_tokens.empty?

    total = term_tokens.sum { |t| name_tokens.map { |n| jaro_winkler(t, n) }.max }
    total / term_tokens.size
  end

  # Jaro-Winkler similarity tra due stringhe (0.0 – 1.0).
  # Specificamente progettato per nomi brevi; premia prefisso iniziale comune.
  # Documentazione algoritmo: https://en.wikipedia.org/wiki/Jaro%E2%80%93Winkler_distance
  def jaro_winkler(s1, s2)
    return 1.0 if s1 == s2
    return 0.0 if s1.empty? || s2.empty?

    len1, len2 = s1.length, s2.length
    match_dist = [[len1, len2].max / 2 - 1, 0].max

    s1_matched = Array.new(len1, false)
    s2_matched = Array.new(len2, false)
    matches = 0

    # Trova caratteri corrispondenti entro la finestra di matching
    (0...len1).each do |i|
      ([0, i - match_dist].max..[len2 - 1, i + match_dist].min).each do |j|
        next if s2_matched[j] || s1[i] != s2[j]
        s1_matched[i] = true
        s2_matched[j] = true
        matches += 1
        break
      end
    end

    return 0.0 if matches.zero?

    # Conta trasposizioni (coppie di match fuori ordine)
    transpositions = 0
    k = 0
    (0...len1).each do |i|
      next unless s1_matched[i]
      k += 1 until s2_matched[k]
      transpositions += 1 if s1[i] != s2[k]
      k += 1
    end

    jaro = (
      matches.to_f / len1 +
      matches.to_f / len2 +
      (matches - transpositions / 2.0) / matches
    ) / 3.0

    # Bonus Winkler: premia prefisso iniziale comune (max 4 caratteri)
    prefix = 0
    [4, len1, len2].min.times { |i| s1[i] == s2[i] ? prefix += 1 : break }

    jaro + prefix * 0.1 * (1.0 - jaro)
  end

  # Token Overlap rimosso: era ridondante con fuzzy_token_score (JW copre già i match esatti)
  # e penalizzava nomi DB con titoli/suffissi ("dott mario rossi" → 0.80 invece di 1.0).

  # Dice Coefficient: similarità a livello di bigrammi
  # Bigramma = coppia di caratteri consecutivi
  # Esempio: "mario" → ["ma", "ar", "ri", "io"]
  # Formula: 2*|overlap bigrammi| / (|left bigrams| + |right bigrams|)
  def dice_coefficient(a, b)
    left = bigrams(a)   # Bigrammi di A
    right = bigrams(b)  # Bigrammi di B
    return 0.0 if left.empty? || right.empty?

    # Conta bigrammi comuni (con molteplicità)
    left_count = left.tally
    right_count = right.tally
    overlap = left_count.sum { |gram, count| [count, right_count[gram].to_i].min }

    (2.0 * overlap) / (left.size + right.size)
  end

  # Genera bigrammi (coppie di caratteri) da un testo
  # Esempio: "mario" → ["ma", "ar", "ri", "io"]
  def bigrams(text)
    return [] if text.length < 2

    text.chars.each_cons(2).map(&:join)
  end
end
