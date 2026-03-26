module DocumentProcessing
  class ProcessGenericFile
    def initialize(
      notifier: nil,
      file_storage: nil,
      generic_file_repository: nil,
      image_processor_factory:,
      csv_processor_factory:
    )
      @notifier = notifier
      @file_storage = file_storage
      @generic_file_repository = generic_file_repository
      @image_processor_factory = image_processor_factory
      @csv_processor_factory = csv_processor_factory
    end

    def call(file_path:, job_id:, uploaded_document_id:, file_kind:, category: nil, override_company: nil, override_department: nil, competence_period: nil)
      uploaded_document = generic_file_repository.find_uploaded_document(uploaded_document_id)
      run = generic_file_repository.find_run_by_job_id(job_id)
      raise ActiveRecord::RecordNotFound, "ProcessingRun not found for job_id=#{job_id}" unless run
      generic_file_repository.mark_run_processing!(run)

      # Build overlay params: user-provided values that override LLM extraction
      overlays = {
        category: category,
        override_company: override_company,
        override_department: override_department,
        competence_period: competence_period
      }

      events = case file_kind.to_s
      when "csv"
        process_csv(file_path, uploaded_document, run, overlays)
      when "image"
        process_image(file_path, uploaded_document, run, overlays)
      else
        raise ArgumentError, "file_kind non supportato: #{file_kind}"
      end

      events.each { |payload| notifier.broadcast(job_id, payload) }
      run.reload
      notifier.broadcast(job_id, event: "processing_completed", status: "success", processed_documents: run.processed_documents, total_documents: run.total_documents)
    rescue StandardError => e
      run&.update(status: "failed", error_message: e.message, completed_at: Time.current)
      notifier.broadcast(job_id, build_error_payload(message: e.message, filename: File.basename(file_path)))
      notifier.broadcast(job_id, event: "processing_completed", status: "error")
    ensure
      file_storage.delete(file_path) if file_path && file_storage.exist?(file_path)
    end

    private

    attr_reader :notifier, :file_storage, :generic_file_repository,
      :image_processor_factory, :csv_processor_factory

    # Apply user-provided overrides to LLM extraction results
    # User overlays take precedence and get confidence = 1.0
    def apply_user_overlays(llm_metadata, llm_confidence, overlays)
      merged_metadata = llm_metadata.dup
      merged_confidence = (llm_confidence || {}).dup

      if overlays[:category].present?
        merged_metadata[:category] = overlays[:category]
        merged_confidence["category"] = 1.0
      end

      if overlays[:override_company].present?
        merged_metadata[:company] = overlays[:override_company]
        merged_confidence["company"] = 1.0
      end

      if overlays[:override_department].present?
        merged_metadata[:department] = overlays[:override_department]
        merged_confidence["department"] = 1.0
      end

      if overlays[:competence_period].present?
        merged_metadata[:competence] = overlays[:competence_period]
        merged_confidence["competence"] = 1.0
      end

      [merged_metadata, merged_confidence]
    end

    def process_csv(file_path, uploaded_document, run, overlays)
      processor = build_csv_processor
      extracted_rows = processor.extract_rows(file_path)

      generic_file_repository.transaction do
        generic_file_repository.set_run_total!(run, extracted_rows.size)

        events = extracted_rows.each_with_index.map do |result, idx|
          seq = idx + 1
          merged_metadata, merged_confidence = apply_user_overlays(result[:metadata], result[:confidence], overlays)

          extracted, item = generic_file_repository.create_csv_item!(
            uploaded_document: uploaded_document,
            run: run,
            sequence: seq,
            metadata: merged_metadata,
            confidence: merged_confidence,
            recipient: result[:recipient],
            employee: result[:employee]
          )

          build_success_payload(
            filename: uploaded_document.original_filename,
            recipient: result[:recipient],
            extracted_document_data: merged_metadata,
            extracted_confidence: merged_confidence,
            matched_recipient: format_employee(result[:employee]),
            extracted_document_id: extracted.id,
            document_index: seq,
            total_documents: extracted_rows.size,
            ocr_text: result[:ocr_text]
          )
        end

        generic_file_repository.mark_run_completed!(run, processed_documents: extracted_rows.size)
        events
      end
    end

    def process_image(file_path, uploaded_document, run, overlays)
      result = build_image_processor.extract(file_path)

      # Apply user overrides (user values + confidence = 1.0)
      merged_metadata, merged_confidence = apply_user_overlays(result[:metadata], result[:confidence], overlays)

      extracted = generic_file_repository.transaction do
        generic_file_repository.set_run_total!(run, 1)

        extracted, _item = generic_file_repository.create_image_item!(
          uploaded_document: uploaded_document,
          run: run,
          metadata: merged_metadata,
          confidence: merged_confidence,
          recipient: result[:recipient],
          employee: result[:employee]
        )

        generic_file_repository.mark_run_completed!(run, processed_documents: 1)
        extracted
      end

      [build_success_payload(
        filename: uploaded_document.original_filename,
        recipient: result[:recipient],
        extracted_document_data: merged_metadata,
        extracted_confidence: merged_confidence || {},
        matched_recipient: format_employee(result[:employee]),
        extracted_document_id: extracted.id,
        document_index: 1,
        total_documents: 1,
        ocr_text: result[:ocr_text]
      )]
    end

    def build_image_processor
      unless image_processor_factory&.respond_to?(:call)
        raise ArgumentError, "image_processor_factory must be provided and respond to :call"
      end

      image_processor_factory.call
    end

    def build_csv_processor
      unless csv_processor_factory&.respond_to?(:call)
        raise ArgumentError, "csv_processor_factory must be provided and respond to :call"
      end

      csv_processor_factory.call
    end

    def build_success_payload(filename:, recipient:, extracted_document_data:, extracted_confidence:, matched_recipient:, extracted_document_id:, document_index:, total_documents:, ocr_text: nil)
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

    def build_error_payload(message:, filename: nil, extracted_document_id: nil)
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
        document_index: nil,
        total_documents: nil,
        message: message
      }
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
