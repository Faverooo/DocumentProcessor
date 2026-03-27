module DocumentProcessing
  class Container
    def initialize(
      aws_region: ENV.fetch("AWS_REGION", "us-east-1"),
      broadcaster: ActionCable.server,
      ocr_service_class: DocumentProcessing::Ocr,
      data_extractor_class: DocumentProcessing::DataExtractor,
      recipient_resolver_class: DocumentProcessing::RecipientResolver,
      pdf_splitter_class: DocumentProcessing::PdfSplitter,
      image_processor_class: DocumentProcessing::ImageProcessor,
      csv_processor_class: DocumentProcessing::CsvProcessor,
      confidence_calculator_class: DocumentProcessing::ConfidenceCalculator,
      extracted_metadata_builder_class: DocumentProcessing::ExtractedMetadataBuilder,
      notifier_class: DocumentProcessing::ActionCableNotifier,
      llm_service_class: DocumentProcessing::LlmService,
      split_run_repository_class: DocumentProcessing::Persistence::SplitRunRepository,
      data_item_repository_class: DocumentProcessing::Persistence::DataItemRepository,
      file_storage_class: DocumentProcessing::Persistence::FileStorage,
      upload_manager_class: DocumentProcessing::UploadManager,
      page_range_pdf_service_class: DocumentProcessing::PageRangePdf,
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
      @image_processor_class = image_processor_class
      @csv_processor_class = csv_processor_class
      @confidence_calculator_class = confidence_calculator_class
      @extracted_metadata_builder_class = extracted_metadata_builder_class
      @notifier_class = notifier_class
      @llm_service_class = llm_service_class
      @split_run_repository_class = split_run_repository_class
      @data_item_repository_class = data_item_repository_class
      @file_storage_class = file_storage_class
      @upload_manager_class = upload_manager_class
      @page_range_pdf_service_class = page_range_pdf_service_class
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

    def image_processor
      @image_processor_class.new(
        ocr_service: ocr_service,
        data_extractor: data_extractor,
        recipient_resolver: recipient_resolver
      )
    end

    def csv_processor
      @csv_processor_class.new(data_extractor: data_extractor, recipient_resolver: recipient_resolver)
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

    def upload_manager
      @upload_manager ||= @upload_manager_class.new
    end

    def page_range_pdf_service_class
      @page_range_pdf_service_class
    end

    def db_manager
      @db_manager ||= @db_manager_class.new(data_item_repository: data_item_repository, recipient_resolver: recipient_resolver)
    end

    def process_data_item_service
      DocumentProcessing::ProcessDataItem.new(
        data_item_repository: data_item_repository,
        notifier: notifier,
        file_storage: file_storage,
        ocr_service: ocr_service,
        data_extractor: data_extractor,
        recipient_resolver: recipient_resolver,
        confidence_calculator_factory: method(:confidence_calculator),
        extracted_metadata_builder_factory: method(:extracted_metadata_builder)
      )
    end

    def process_split_run_service
      DocumentProcessing::ProcessSplitRun.new(
        split_run_repository: split_run_repository,
        notifier: notifier,
        file_storage: file_storage,
        pdf_splitter_factory: method(:pdf_splitter),
        data_extraction_job_class: DataExtractionJob
      )
    end

    def process_generic_file_service
      DocumentProcessing::ProcessGenericFile.new(
        notifier: notifier,
        file_storage: file_storage,
        generic_file_repository: data_item_repository,
        image_processor_factory: method(:image_processor),
        csv_processor_factory: method(:csv_processor),
        confidence_calculator_factory: method(:confidence_calculator)
      )
    end

    def initialize_processing_command
      DocumentProcessing::Commands::InitializeProcessing.new(
        upload_manager: upload_manager,
        pdf_split_job_class: PdfSplitJob,
        pdf_loader: CombinePDF,
        file_storage: file_storage
      )
    end

    def initialize_file_processing_command
      DocumentProcessing::Commands::InitializeFileProcessing.new(
        upload_manager: upload_manager,
        generic_file_processing_job_class: GenericFileProcessingJob,
        file_storage: file_storage
      )
    end

    def reassign_extracted_range_command
      DocumentProcessing::Commands::ReassignExtractedRange.new(
        page_range_pdf_service_class: page_range_pdf_service_class,
        data_extraction_job_class: DataExtractionJob,
        file_storage: file_storage
      )
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
