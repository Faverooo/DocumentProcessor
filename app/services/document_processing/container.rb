module DocumentProcessing
  class Container
    def initialize(aws_region: ENV.fetch("AWS_REGION", "us-east-1"), broadcaster: ActionCable.server)
      @aws_region = aws_region
      @broadcaster = broadcaster
    end

    def ocr_service
      @ocr_service ||= DocumentOcrService.new(textract_client: textract_client)
    end

    def recipient_extractor
      @recipient_extractor ||= DocumentRecipientExtractorService.new(llm_service: llm_service)
    end

    def recipient_resolver
      @recipient_resolver ||= DocumentRecipientResolverService.new
    end

    def pdf_splitter(pdf:)
      DocumentPdfSplitterService.new(pdf: pdf, ocr_service: ocr_service, llm_service: llm_service)
    end

    def notifier
      @notifier ||= ActionCableNotifier.new(broadcaster: @broadcaster)
    end

    def broadcast(job_id, data)
      notifier.broadcast(job_id, data)
    end

    private

    def textract_client
      @textract_client ||= Aws::Textract::Client.new(region: @aws_region)
    end

    def bedrock_client
      @bedrock_client ||= Aws::BedrockRuntime::Client.new(region: @aws_region)
    end

    def llm_service
      @llm_service ||= LlmService.new(bedrock_client: bedrock_client)
    end
  end
end
