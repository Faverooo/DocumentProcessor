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
  def initialize(bedrock_client: Aws::BedrockRuntime::Client.new)
    @bedrock = bedrock_client  # Client AWS Bedrock
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

  attr_reader :bedrock

  # Invia il testo a Amazon Nova Lite e riceve la risposta in JSON
  def ask_llm_for_recipients(text)
    response = bedrock.invoke_model(
      model_id: ENV.fetch("BEDROCK_MODEL_ID", "amazon.nova-lite-v1:0"),
      body: request_body(text),
      content_type: "application/json",
      accept: "application/json"
    )

    # Formato risposta Amazon Nova: output.message.content[0].text
    parsed_response = JSON.parse(response.body.read)
    content = parsed_response.dig("output", "message", "content", 0, "text").to_s

    # Estrai JSON dalla risposta anche se il LLM aggiunge testo introduttivo
    # Cerca il primo oggetto JSON { ... } nella risposta
    json_match = content.match(/\{.*\}/m)
    raise "Nessun JSON trovato nella risposta LLM" unless json_match

    JSON.parse(json_match[0])
  end

  # Costruisce il body della richiesta Bedrock per Amazon Nova Lite
  # Formato Nova: messages con content array, inferenceConfig separato (diverso da Claude)
  def request_body(text)
    {
      messages: [
        { role: "user", content: [{ text: prompt(text) }] }
      ],
      inferenceConfig: {
        maxTokens: 350,    # Massimo spazio per la risposta
        temperature: 0.0   # Zero creatività (massima precisione)
      }
    }.to_json
  end

  # Prompt per Amazon Nova Lite: estrai SOLO destinatari, non menzioni secondarie
  def prompt(text)
    <<~PROMPT
      Estrai SOLO i destinatari principali del documento.
      Non includere persone citate nel corpo testo, firme, referenti, mittenti o menzioni secondarie.

      Restituisci SOLO JSON valido in questo formato:
      {"recipients":[{"name":"Nome Cognome"}]}

      Se non trovi destinatari certi, restituisci:
      {"recipients":[]}

      Testo OCR documento:
      ---
      #{text}
      ---
    PROMPT
  end

  # Pulisce il nome: rimuove spazi extra, scarta se troppo corto
  def normalize_name(name)
    cleaned = name.to_s.gsub(/\s+/, " ").strip
    return nil if cleaned.blank? || cleaned.length < 3

    cleaned
  end
end
