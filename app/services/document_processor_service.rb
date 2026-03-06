require "combine_pdf"
require "aws-sdk-textract"
require "aws-sdk-bedrockruntime"

# === DocumentProcessorService ===
# Orchestratore principale del flusso di elaborazione documenti.
# 
# Flusso completo:
# 1. Carica il PDF multi-documento (es. cedolini)
# 2. Divide in mini-PDF via DocumentPdfSplitterService
# 3. Per ogni mini-PDF:
#    - Estrae testo via Textract (DocumentOcrService)
#    - Estrae destinatari via Nova Lite LLM (DocumentRecipientExtractorService)
#    - Matcha con dipendenti aziendali (DocumentRecipientResolverService)
#    - Salva ProcessedDocument nel DB
#
class DocumentProcessorService
  def initialize(
    file_path,
    ocr_service: DocumentOcrService.new,
    bedrock_client: Aws::BedrockRuntime::Client.new,
    recipient_extractor: nil,
    recipient_resolver: DocumentRecipientResolverService.new,
    pdf_splitter_service: nil
  )
    @file_path = file_path
    @pdf_original = CombinePDF.load(file_path)  # Carica il PDF con CombinePDF
    @ocr_service = ocr_service                  # Servizio Textract per OCR
    @recipient_extractor = recipient_extractor || DocumentRecipientExtractorService.new(bedrock_client: bedrock_client)
    @recipient_resolver = recipient_resolver    # Servizio fuzzy matching locale
    @pdf_splitter_service = pdf_splitter_service || DocumentPdfSplitterService.new(
      pdf: @pdf_original,
      ocr_service: ocr_service,
      bedrock_client: bedrock_client
    )
  end

  # Esegue il flusso completo di elaborazione
  def call
    @pdf_splitter_service.split.each { |mini_pdf_path| analyze_and_dispatch(mini_pdf_path) }
    true  # Ritorna true al completamento
  end

  private
# attr_reader crea automaticamente metodi getter che permettono di accedere 
# alle variabili di istanza (indicate con @) in modo più pulito. Invece di scrivere @file_path, puoi scrivere semplicemente file_path.
  attr_reader :file_path, :pdf_original, :ocr_service, :recipient_extractor, :recipient_resolver

  # Analizza un singolo mini-PDF e salva il ProcessedDocument
  # Steps:
  #   1. OCR del documento via Textract
  #   2. Estrazione nomi destinatari via Claude LLM
  #   3. Fuzzy match against Employee table
  #   4. Salvataggio in DB con collegamento a Employee
  #   5. Pulizia del file temporaneo
  def analyze_and_dispatch(mini_pdf_path)
    raw_text = ocr_service.full_ocr(mini_pdf_path)              # Step 1: OCR
    recipient_names = recipient_extractor.extract(raw_text)     # Step 2: LLM extraction
    recipient = recipient_resolver.resolve(recipient_names:, raw_text:)  # Step 3: Fuzzy match

    if recipient
      ProcessedDocument.create!(                                 # Step 4: Salva nel DB
        filename: File.basename(mini_pdf_path),
        status: "processed",
        recipient_name: recipient.name,
        employee: recipient  # Foreign key verso Employee
      )
      Rails.logger.info("Destinatario trovato: #{recipient.name}")
    else
      Rails.logger.warn("Documento non riconosciuto: #{File.basename(mini_pdf_path)}")
    end
  ensure
    File.delete(mini_pdf_path) if mini_pdf_path && File.exist?(mini_pdf_path)  # Step 5: Cleanup
  end
end
