module DocumentProcessing
  class ProcessDataItem
    def initialize(container:)
      @container = container
    end

    def call(file_path:, job_id:, processing_item_id: nil, extracted_document_id: nil)
      start_time = Time.now
      run = data_item_repository.find_run_by_job_id(job_id)
      item = processing_item_id ? data_item_repository.find_processing_item(processing_item_id) : nil
      extracted_document = resolve_extracted_document(extracted_document_id, item)

      return if data_item_repository.terminal_item?(item)

      data_item_repository.mark_item_in_progress!(item)
      data_item_repository.mark_extracted_document_in_progress!(extracted_document)

      ocr_result = container.ocr_service.full_ocr(file_path)
      full_text = ocr_result[:text]
      ocr_lines = ocr_result[:lines]

      extracted_data = container.data_extractor.extract(full_text)
      recipient_names = extracted_data[:recipients]
      extracted_document_data = extracted_data[:metadata]
      llm_confidence = extracted_data[:llm_confidence]
      final_global_confidence = container.confidence_calculator(
        ocr_lines: ocr_lines,
        recipient_names: recipient_names,
        metadata: extracted_document_data,
        llm_confidence: llm_confidence,
        uploaded_document: extracted_document&.uploaded_document
      ).global_confidence

      resolution = container.recipient_resolver.resolve(recipient_names:, raw_text: full_text)

      data_item_repository.mark_item_done!(item:, resolution:)
      duration = Time.now - start_time
      update_extracted_document_success(extracted_document, resolution, extracted_document_data, recipient_names, final_global_confidence, duration)

      if job_id.present?
        notifier.broadcast(
          job_id,
          event: "document_processed",
          status: "success",
          filename: File.basename(file_path),
          ocr_text: full_text,
          extracted_names: recipient_names,
          extracted_document_data: extracted_document_data,
          extracted_confidence: final_global_confidence,
          matched_recipient: format_employee(resolution.employee),
          fallback_text: resolution.unmatched? ? resolution.fallback_text : nil,
          extracted_document_id: extracted_document&.id
        )
      end
    rescue StandardError => e
      data_item_repository.mark_item_failed(item:, error_message: e.message)
      data_item_repository.mark_extracted_document_failed(extracted_document:, error_message: e.message)

      if job_id.present?
        notifier.broadcast(
          job_id,
          event: "document_processed",
          status: "error",
          filename: file_path ? File.basename(file_path) : nil,
          message: e.message,
          extracted_document_id: extracted_document&.id
        )
      end
    ensure
      increment_progress(run, job_id)
      file_storage.delete(file_path) if file_path && file_storage.exist?(file_path)
    end

    private

    attr_reader :container

    def notifier
      container.notifier
    end

    def resolve_extracted_document(extracted_document_id, item) #cerca prima su extraced_document_id, poi su item.associated extracted_document, nil se non trova nulla
      return data_item_repository.find_extracted_document(extracted_document_id) if extracted_document_id.present?
      return nil unless item&.respond_to?(:extracted_document)

      item.extracted_document
    end

    def update_extracted_document_success(extracted_document, resolution, metadata, recipients, global_confidence, process_duration_seconds)
      return unless extracted_document

      uploaded_document = extracted_document.uploaded_document
      metadata_builder = container.extracted_metadata_builder(metadata:, uploaded_document:)

      data_item_repository.mark_extracted_document_done!(
        extracted_document: extracted_document,
        resolution: resolution,
        metadata: metadata_builder.build,
        recipients: recipients,
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

    def data_item_repository
      container.data_item_repository
    end

    def file_storage
      container.file_storage
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

  end
end