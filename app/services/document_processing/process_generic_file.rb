module DocumentProcessing
  class ProcessGenericFile
    def initialize(container:)
      @container = container
    end

    def call(file_path:, job_id:, uploaded_document_id:, file_kind:, category: nil, override_company: nil, override_department: nil, competence_period: nil)
      uploaded_document = UploadedDocument.find(uploaded_document_id)
      run = ProcessingRun.find_by!(job_id: job_id)
      run.update!(status: "processing", started_at: Time.current)

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

    attr_reader :container

    def notifier
      container.notifier
    end

    def file_storage
      container.file_storage
    end

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
      processor = DocumentProcessing::CsvProcessor.new
      extracted_rows = processor.extract_rows(file_path, container)
      events = []

      ProcessingRun.transaction do
        run.update!(total_documents: extracted_rows.size)

        extracted_rows.each_with_index do |result, idx|
          seq = idx + 1
          extracted = uploaded_document.extracted_documents.create!(
            sequence: seq,
            page_start: 1,
            page_end: 1,
            status: "queued"
          )
          item = run.processing_items.create!(
            sequence: seq,
            filename: "#{uploaded_document.original_filename}-row#{seq}",
            status: "queued",
            extracted_document: extracted
          )

          # Apply user overrides (user values + confidence = 1.0)
          merged_metadata, merged_confidence = apply_user_overlays(result[:metadata], result[:confidence], overlays)

          extracted.update!(
            metadata: merged_metadata,
            recipient: result[:recipient],
            confidence: merged_confidence,
            status: "done",
            processed_at: Time.current,
            matched_employee: result[:employee]
          )
          item.update!(status: "done")

          events << build_success_payload(
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

        run.update!(processed_documents: extracted_rows.size, status: "completed", completed_at: Time.current)
      end

      events
    end

    def process_image(file_path, uploaded_document, run, overlays)
      result = DocumentProcessing::ImageProcessor.new(container: container).extract(file_path)

      # Apply user overrides (user values + confidence = 1.0)
      merged_metadata, merged_confidence = apply_user_overlays(result[:metadata], result[:confidence], overlays)

      extracted = nil
      ProcessingRun.transaction do
        run.update!(total_documents: 1)

        extracted = uploaded_document.extracted_documents.create!(
          sequence: 1,
          page_start: 1,
          page_end: 1,
          status: "done",
          metadata: merged_metadata,
          recipient: result[:recipient],
          confidence: merged_confidence || {},
          processed_at: Time.current,
          matched_employee: result[:employee]
        )

        run.processing_items.create!(
          sequence: 1,
          filename: uploaded_document.original_filename,
          status: "done",
          extracted_document: extracted
        )

        run.update!(processed_documents: 1, status: "completed", completed_at: Time.current)
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
