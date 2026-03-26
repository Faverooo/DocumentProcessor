module DocumentProcessing
  class ProcessDataItem
    def initialize(
      data_item_repository:,
      notifier:,
      file_storage:,
      ocr_service:,
      data_extractor:,
      recipient_resolver:,
      confidence_calculator_factory:,
      extracted_metadata_builder_factory:
    )
      @data_item_repository = data_item_repository
      @notifier = notifier
      @file_storage = file_storage
      @ocr_service = ocr_service
      @data_extractor = data_extractor
      @recipient_resolver = recipient_resolver
      @confidence_calculator_factory = confidence_calculator_factory
      @extracted_metadata_builder_factory = extracted_metadata_builder_factory
    end

    def call(file_path:, job_id:, processing_item_id: nil, extracted_document_id: nil)
      start_time = Time.now
      run = data_item_repository.find_run_by_job_id(job_id)
      item = processing_item_id ? data_item_repository.find_processing_item(processing_item_id) : nil
      extracted_document = resolve_extracted_document(extracted_document_id, item)

      return if data_item_repository.terminal_item?(item)

      data_item_repository.mark_item_in_progress!(item)
      data_item_repository.mark_extracted_document_in_progress!(extracted_document)

      ocr_result = ocr_service.full_ocr(file_path)
      full_text = ocr_result[:text]
      ocr_lines = ocr_result[:lines]

      extracted_data = data_extractor.extract(full_text)
      recipient_names = extracted_data[:recipients]
      # Normalize to single recipient: take first extracted name if any
      recipient = Array(recipient_names).compact.first
      extracted_document_data = extracted_data[:metadata]
      llm_confidence = extracted_data[:llm_confidence]
      final_global_confidence = confidence_calculator_factory.call(
        ocr_lines: ocr_lines,
        recipient_names: recipient_names,
        metadata: extracted_document_data,
        llm_confidence: llm_confidence,
        uploaded_document: extracted_document&.uploaded_document
      ).global_confidence

      resolution = recipient_resolver.resolve(recipient_names:, raw_text: full_text)

      data_item_repository.mark_item_done!(item:, resolution:)
      duration = Time.now - start_time
      update_extracted_document_success(extracted_document, resolution, extracted_document_data, recipient, final_global_confidence, duration)

      if job_id.present?
        notifier.broadcast(
          job_id,
          build_success_payload(
            filename: File.basename(file_path),
            ocr_text: full_text,
            recipient: recipient,
            extracted_document_data: extracted_document_data,
            extracted_confidence: final_global_confidence,
            matched_recipient: format_employee(resolution.employee),
            extracted_document_id: extracted_document&.id,
            document_index: item&.sequence,
            total_documents: run&.total_documents
          )
        )
      end
    rescue StandardError => e
      data_item_repository.mark_item_failed(item:, error_message: e.message)
      data_item_repository.mark_extracted_document_failed(extracted_document:, error_message: e.message)

      if job_id.present?
        notifier.broadcast(
          job_id,
          build_error_payload(
            message: e.message,
            filename: file_path ? File.basename(file_path) : nil,
            extracted_document_id: extracted_document&.id,
            document_index: item&.sequence,
            total_documents: run&.total_documents
          )
        )
      end
    ensure
      increment_progress(run, job_id)
      file_storage.delete(file_path) if file_path && file_storage.exist?(file_path)
    end

    private

    attr_reader :data_item_repository, :notifier, :file_storage, :ocr_service, :data_extractor, :recipient_resolver,
      :confidence_calculator_factory, :extracted_metadata_builder_factory

    def resolve_extracted_document(extracted_document_id, item) #cerca prima su extraced_document_id, poi su item.associated extracted_document, nil se non trova nulla
      return data_item_repository.find_extracted_document(extracted_document_id) if extracted_document_id.present?
      return nil unless item&.respond_to?(:extracted_document)

      item.extracted_document
    end

    def update_extracted_document_success(extracted_document, resolution, metadata, recipient, global_confidence, process_duration_seconds)
      return unless extracted_document

      uploaded_document = extracted_document.uploaded_document
      metadata_builder = extracted_metadata_builder_factory.call(metadata:, uploaded_document:)

      data_item_repository.mark_extracted_document_done!(
        extracted_document: extracted_document,
        resolution: resolution,
        metadata: metadata_builder.build,
        recipient: recipient,
        global_confidence: global_confidence,
        process_duration_seconds: process_duration_seconds
      )
    end

    def increment_progress(run, job_id)
      result = data_item_repository.update_progress!(run)
      return unless result[:completed]

      notifier.broadcast(
        job_id,
        event: "processing_completed",
        status: "success"
      )
    end

    def format_employee(employee)
      return nil unless employee.is_a?(Employee)

      {
        id: employee.id,
        name: employee.name,
        email: employee.email,
        employee_code: employee.employee_code
      }
    end

    def build_success_payload(filename:, ocr_text:, recipient:, extracted_document_data:, extracted_confidence:, matched_recipient:, extracted_document_id:, document_index:, total_documents:)
      {
        event: "document_processed",
        status: "success",
        filename: filename,
        ocr_text: ocr_text,
        recipient: recipient,
        extracted_document_data: extracted_document_data || {},
        extracted_confidence: extracted_confidence || {},
        matched_recipient: matched_recipient,
        extracted_document_id: extracted_document_id,
        document_index: document_index,
        total_documents: total_documents,
        message: nil
      }
    end

    def build_error_payload(message:, filename:, extracted_document_id:, document_index:, total_documents:)
      {
        event: "document_processed",
        status: "error",
        filename: filename,
        ocr_text: nil,
        recipient: nil,
        extracted_document_data: {},
        extracted_confidence: {},
        matched_recipient: nil,
        extracted_document_id: extracted_document_id,
        document_index: document_index,
        total_documents: total_documents,
        message: message
      }
    end

  end
end
