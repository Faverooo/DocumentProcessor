module DocumentProcessing
  class Container
    def initialize(
      aws_region: ENV.fetch("AWS_REGION", "us-east-1"),
      broadcaster: ActionCable.server,
      ocr_service_class: DocumentProcessing::Ocr,
      data_extractor_class: DocumentProcessing::DataExtractor,
      recipient_resolver_class: DocumentProcessing::RecipientResolver,
      pdf_splitter_class: DocumentProcessing::PdfSplitter,
      confidence_calculator_class: DocumentProcessing::ConfidenceCalculator,
      extracted_metadata_builder_class: DocumentProcessing::ExtractedMetadataBuilder,
      notifier_class: DocumentProcessing::ActionCableNotifier,
      llm_service_class: DocumentProcessing::LlmService,
      split_run_repository_class: DocumentProcessing::Persistence::SplitRunRepository,
      data_item_repository_class: DocumentProcessing::Persistence::DataItemRepository,
      file_storage_class: DocumentProcessing::Persistence::FileStorage,
      db_manager_class: DocumentProcessing::Persistence::DbManager,
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
      @split_run_repository_class = split_run_repository_class
      @data_item_repository_class = data_item_repository_class
      @file_storage_class = file_storage_class
      @db_manager_class = db_manager_class
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

    def split_run_repository
      @split_run_repository ||= @split_run_repository_class.new
    end

    def data_item_repository
      @data_item_repository ||= @data_item_repository_class.new
    end

    def file_storage
      @file_storage ||= @file_storage_class.new
    end

    def db_manager
      @db_manager ||= @db_manager_class.new(data_item_repository: data_item_repository)
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
