module DocumentProcessing
  class LlmService
    DEFAULT_MODEL_ID = "amazon.nova-lite-v1:0".freeze

    def initialize(bedrock_client:, model_id: ENV.fetch("BEDROCK_MODEL_ID", DEFAULT_MODEL_ID))
      @bedrock_client = bedrock_client
      @model_id = model_id
    end

    def extract_document_data(text)
      converse_json(
        system_prompt: document_data_extraction_system_prompt,
        user_prompt: document_data_extraction_user_prompt(text),
        max_tokens: 350,
        temperature: 0.0
      )
    end

    def detect_split_breakpoints(summary)
      converse_json(
        system_prompt: split_breakpoints_system_prompt,
        user_prompt: split_breakpoints_user_prompt(summary),
        max_tokens: 500,
        temperature: 0.0
      )
    end

    private

    attr_reader :bedrock_client, :model_id

    def converse_json(system_prompt:, user_prompt:, max_tokens:, temperature: 0.0)
      response = bedrock_client.converse(
        model_id: model_id,
        system: [{ text: system_prompt }],
        messages: [
          {
            role: "user",
            content: [{ text: user_prompt }]
          }
        ],
        inference_config: {
          max_tokens: max_tokens,
          temperature: temperature
        }
      )

      extract_json_from_text(response_text(response))
    end

    def response_text(response)
      content_items = if response.respond_to?(:output) && response.output.respond_to?(:message)
        response.output.message.content
      else
        response.dig("output", "message", "content")
      end

      Array(content_items).map { |item| content_text(item) }.join("\n").strip
    end

    def content_text(item)
      return item.text.to_s if item.respond_to?(:text)
      return item[:text].to_s if item.is_a?(Hash) && item.key?(:text)
      return item["text"].to_s if item.is_a?(Hash)

      item.to_s
    end

    def extract_json_from_text(text)
      json_match = text.match(/\{.*\}/m)
      raise "Nessun JSON trovato nella risposta LLM" unless json_match

      JSON.parse(json_match[0])
    end

    def document_data_extraction_system_prompt
      <<~PROMPT
        Sei un sistema di estrazione strutturata.
        Devi identificare solo i destinatari principali del documento.
        Inoltre devi estrarre, se presenti e affidabili, i metadati principali del documento: data, azienda, reparto, tipo (categoria).
        Non includere firme, mittenti, referenti interni, persone citate nel corpo testo o menzioni secondarie.
        Se un dato non e certo, valorizzalo a null.
        Rispondi sempre e solo con JSON valido.
      PROMPT
    end

    def document_data_extraction_user_prompt(text)
      <<~PROMPT
        Estrai i destinatari principali e i metadati principali del documento.

        Formato output obbligatorio:
        {"recipients":[{"name":"Nome Cognome"}],"document":{"date":"YYYY-MM-DD or null","company":"Nome Azienda or null","department":"Nome Reparto or null","type":"Tipo/Category or null","reason":"Causale or null","competence":"Competence/period or null"},"confidence":{"recipient":0.0,"date":0.0,"company":0.0,"department":0.0,"type":0.0,"reason":0.0,"competence":0.0}}

        Regole:
        - recipients contiene solo destinatari principali.
        - document.date deve essere in formato ISO YYYY-MM-DD quando possibile, altrimenti null.
        - Se company, department, type, reason o competence non sono chiari, usa null.
        - confidence contiene valori tra 0.0 e 1.0 per ogni campo (inclusi `reason` e `competence`).
        - Se un campo e' assente o dubbio, la sua confidence deve essere 0.0.

        Se non trovi destinatari certi, lascia recipients vuoto ma compila comunque document dove possibile:
        {"recipients":[],"document":{"date":null,"company":null,"department":null,"type":null,"reason":null,"competence":null},"confidence":{"recipient":0.0,"date":0.0,"company":0.0,"department":0.0,"type":0.0,"reason":0.0,"competence":0.0}}

        Testo OCR documento:
        ---
        #{text}
        ---
      PROMPT
    end

    def split_breakpoints_system_prompt
      <<~PROMPT
        Sei un sistema di segmentazione documentale.
        Devi individuare dove iniziano nuovi documenti dentro un PDF composto da piu documenti consecutivi.
        Rispondi sempre e solo con JSON valido.
      PROMPT
    end

    def split_breakpoints_user_prompt(summary)
      <<~PROMPT
        Identifica le pagine che iniziano un nuovo documento.

        CRITERI DI IDENTIFICAZIONE:
        1. Cambio di destinatario, matricola o identificativo.
        2. Intestazioni identiche che si ripetono per un nuovo soggetto.
        3. Cambio netto di struttura o layout.
        4. Numerazione che riparte da pagina 1.

        REGOLE:
        - La PAGINA 0 e sempre l'inizio del primo documento.
        - Documenti dello stesso tipo per persone diverse sono separati.
        - Un documento puo occupare una o piu pagine consecutive.
        - Usa esattamente gli indici mostrati nelle anteprime.

        ESEMPI:
        PAGINA 0: Cedolino - Dipendente Mario Rossi
        PAGINA 1: Cedolino - Dipendente Anna Bianchi
        PAGINA 2: Cedolino - Dipendente Luca Verdi
        -> {"start_pages": [0, 1, 2]}

        PAGINA 0: Fattura 001 - Cliente ABC (Pag 1/2)
        PAGINA 1: Fattura 001 - Cliente ABC (Pag 2/2)
        PAGINA 2: Fattura 002 - Cliente XYZ (Pag 1/1)
        -> {"start_pages": [0, 2]}

        PAGINA 0: Contratto (Pag 1/5)
        PAGINA 1: Contratto (Pag 2/5)
        -> {"start_pages": [0]}

        Formato output obbligatorio:
        {"start_pages": [0, 3, 7]}

        ANTEPRIME PAGINE:
        #{summary}
      PROMPT
    end
  end
end