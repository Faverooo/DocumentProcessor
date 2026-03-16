# === DocumentRecipientExtractorService ===
# Estrae i destinatari da un documento usando Amazon Nova Lite v1 via AWS Bedrock.
#
# Logica:
#   1. Manda il testo OCR a Nova con prompt specifico
#   2. Nova estrae SOLO i destinatari (ignora menzioni secondarie)
#   3. Ritorna array di nomi normalizzati
#
# Nota: Nova Lite è rapido e cost-effective per destinatari extraction.
#
class DocumentRecipientExtractorService
  def initialize(llm_service: nil, bedrock_client: Aws::BedrockRuntime::Client.new)
    @llm_service = llm_service || DocumentProcessing::LlmService.new(bedrock_client: bedrock_client)
  end

  # Estrae destinatari dal testo OCR
  # Ritorna: ["Mario Rossi", "Anna Bianchi"] oppure []
  def extract(text)
    return [] if text.to_s.strip.blank?

    parsed = ask_llm_for_recipients(text)  # Chiama Nova Lite via Bedrock
    
    # Estrai nomi e normalizza
    recipients = Array(parsed["recipients"]).filter_map do |entry|
      normalize_name(entry["name"] || entry[:name])
    end

    recipients.uniq  # Rimuovi duplicati
  rescue StandardError => error
    Rails.logger.error("Errore estrazione destinatari LLM: #{error.message}")
    []  # Fallback: ritorna lista vuota
  end

  private

  attr_reader :llm_service

  # Invia il testo a Amazon Nova Lite via Converse e riceve la risposta in JSON
  def ask_llm_for_recipients(text)
    llm_service.extract_recipients(text)
  end

  # Pulisce il nome: rimuove spazi extra, scarta se troppo corto
  def normalize_name(name)
    cleaned = name.to_s.gsub(/\s+/, " ").strip
    return nil if cleaned.blank? || cleaned.length < 3

    cleaned
  end
end
