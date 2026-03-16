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

  # Estrae destinatari e metadati dal testo OCR
  # Ritorna:
  # {
  #   recipients: ["Mario Rossi", "Anna Bianchi"],
  #   metadata: { date: "2026-03-16", company: "ACME", department: "HR" }
  # }
  def extract(text)
    return empty_extraction if text.to_s.strip.blank?

    parsed = ask_llm_for_recipients(text)  # Chiama Nova Lite via Bedrock

    # Estrai nomi e normalizza
    recipients = Array(parsed["recipients"]).filter_map do |entry|
      normalize_name(entry["name"] || entry[:name])
    end

    {
      recipients: recipients.uniq, # Rimuovi duplicati
      metadata: extract_metadata(parsed)
    }
  rescue StandardError => error
    Rails.logger.error("Errore estrazione destinatari LLM: #{error.message}")
    empty_extraction
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

  def extract_metadata(parsed)
    document_data = parsed["document"] || parsed[:document] || {}

    {
      date: normalize_field(
        document_data["date"] ||
        document_data[:date] ||
        parsed["date"] ||
        parsed[:date]
      ),
      company: normalize_field(
        document_data["company"] ||
        document_data[:company] ||
        parsed["company"] ||
        parsed[:company]
      ),
      department: normalize_field(
        document_data["department"] ||
        document_data[:department] ||
        parsed["department"] ||
        parsed[:department]
      )
    }
  end

  def normalize_field(value)
    cleaned = value.to_s.gsub(/\s+/, " ").strip
    cleaned.presence
  end

  def empty_extraction
    {
      recipients: [],
      metadata: {
        date: nil,
        company: nil,
        department: nil
      }
    }
  end
end
