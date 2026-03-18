module DocumentProcessing
  class ProcessDataItem
    def initialize(container:)
      @container = container
    end

    def call(file_path:, job_id:, processing_item_id: nil, extracted_document_id: nil)
      start_time = Time.now
      run = ProcessingRun.find_by(job_id: job_id)
      item = processing_item_id ? ProcessingItem.find_by(id: processing_item_id) : nil
      extracted_document = resolve_extracted_document(extracted_document_id, item)

      return if already_terminal_item?(item)

      mark_item_in_progress(item)
      mark_extracted_document_in_progress(extracted_document)

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

      update_item_success(item, resolution)
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
      item&.update(status: "failed", error_message: e.message)
      extracted_document&.update(status: "failed", error_message: e.message)

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
      File.delete(file_path) if file_path && File.exist?(file_path)
    end

    private

    attr_reader :container

    def notifier
      container.notifier
    end

    def already_terminal_item?(item)
      return false unless item

      item.with_lock do
        item.reload
        item.done? || item.failed?
      end
    end

    def mark_item_in_progress(item)
      return unless item

      item.with_lock do
        item.reload
        item.update!(status: "in_progress") unless item.done? || item.failed?
      end
    end

    def update_item_success(item, resolution)
      item&.update!(
        status: "done",
        recipient_name: resolution.matched? ? resolution.employee.name : nil,
        matched_employee: resolution.matched? ? resolution.employee : nil,
        error_message: nil
      )
    end

    def resolve_extracted_document(extracted_document_id, item) #cerca prima su extraced_document_id, poi su item.associated extracted_document, nil se non trova nulla
      return ExtractedDocument.find_by(id: extracted_document_id) if extracted_document_id.present?
      return nil unless item&.respond_to?(:extracted_document)

      item.extracted_document
    end

    def mark_extracted_document_in_progress(extracted_document)
      return unless extracted_document

      extracted_document.with_lock do
        extracted_document.reload
        extracted_document.update!(status: "in_progress") unless extracted_document.done? || extracted_document.failed?
      end
    end

    def update_extracted_document_success(extracted_document, resolution, metadata, recipients, global_confidence, process_duration_seconds)
      return unless extracted_document

      uploaded_document = extracted_document.uploaded_document
      metadata_builder = container.extracted_metadata_builder(metadata:, uploaded_document:)

      extracted_document.update!(
        status: "done",
        metadata: metadata_builder.build,
        recipients: recipients,
        fallback_text: resolution&.fallback_text,
        confidence: global_confidence,
        document_type: (metadata_builder.document_type || extracted_document.document_type),
        process_time_seconds: process_duration_seconds.to_f,
        recipient_name: resolution.matched? ? resolution.employee.name : nil,
        matched_employee: resolution.matched? ? resolution.employee : nil,
        error_message: nil,
        processed_at: Time.current
      )
    end

    def increment_progress(run, job_id)
      return if run.nil?

      done = run.processing_items.where(status: %w[done failed]).count
      total = run.total_documents

      run.update!(processed_documents: done)
      return if done.nil? || total.nil? || done != total

      run.update!(status: "completed", completed_at: Time.current)
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

  end
end