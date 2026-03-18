module DocumentProcessing
  class Container
    def initialize(
      aws_region: ENV.fetch("AWS_REGION", "us-east-1"),
      broadcaster: ActionCable.server,
      ocr_service_class: DocumentOcrService,
      data_extractor_class: DocumentDataExtractorService,
      recipient_resolver_class: DocumentRecipientResolverService,
      pdf_splitter_class: DocumentPdfSplitterService,
      confidence_calculator_class: DocumentProcessing::ConfidenceCalculator,
      extracted_metadata_builder_class: DocumentProcessing::ExtractedMetadataBuilder,
      notifier_class: DocumentProcessing::ActionCableNotifier,
      llm_service_class: DocumentProcessing::LlmService,
      textract_client: nil,
      bedrock_client: nil
    )
      @aws_region = aws_region
      @broadcaster = broadcaster
      @ocr_service_class = ocr_service_class
      @data_extractor_class = data_extractor_class
      @recipient_resolver_class = recipient_resolver_class
      @pdf_splitter_class = pdf_splitter_class
      @confidence_calculator_class = confidence_calculator_class
      @extracted_metadata_builder_class = extracted_metadata_builder_class
      @notifier_class = notifier_class
      @llm_service_class = llm_service_class
      @textract_client = textract_client
      @bedrock_client = bedrock_client
    end

    def ocr_service
      @ocr_service ||= @ocr_service_class.new(textract_client: textract_client)
    end

    def data_extractor
      @data_extractor ||= @data_extractor_class.new(llm_service: llm_service)
    end

    def recipient_resolver
      @recipient_resolver ||= @recipient_resolver_class.new
    end

    def pdf_splitter(pdf:)
      @pdf_splitter_class.new(pdf: pdf, ocr_service: ocr_service, llm_service: llm_service)
    end

    def confidence_calculator(**kwargs)
      @confidence_calculator_class.new(**kwargs)
    end

    def extracted_metadata_builder(**kwargs)
      @extracted_metadata_builder_class.new(**kwargs)
    end

    def notifier
      @notifier ||= @notifier_class.new(broadcaster: @broadcaster)
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
      @llm_service ||= @llm_service_class.new(bedrock_client: bedrock_client)
    end
  end
end
