module DocumentProcessing
  class ProcessDataItem
    def initialize(container:)
      @container = container
    end

    def call(file_path:, job_id:, processing_item_id: nil)
      run = ProcessingRun.find_by(job_id: job_id)
      item = processing_item_id ? ProcessingItem.find_by(id: processing_item_id) : nil
      return if already_terminal_item?(item)

      mark_item_in_progress(item)

      ocr_result = container.ocr_service.full_ocr(file_path)
      full_text = ocr_result[:text]
      ocr_lines = ocr_result[:lines]

      extracted_data = container.data_extractor.extract(full_text)
      recipient_names = extracted_data[:recipients]
      extracted_document_data = extracted_data[:metadata]
      llm_confidence = extracted_data[:llm_confidence]
      textract_confidence = compute_textract_confidence(
        ocr_lines: ocr_lines,
        recipient_names: recipient_names,
        metadata: extracted_document_data
      )
      global_confidence = build_global_confidence(llm_confidence, textract_confidence)

      resolution = container.recipient_resolver.resolve(recipient_names:, raw_text: full_text)

      update_item_success(item, resolution)

      notifier.broadcast(
        job_id,
        event: "document_processed",
        status: "success",
        filename: File.basename(file_path),
        ocr_text: full_text,
        extracted_names: recipient_names,
        extracted_document_data: extracted_document_data,
        extracted_confidence: {
          global: global_confidence,
          llm: llm_confidence,
          textract: textract_confidence
        },
        matched_recipient: format_employee(resolution.employee),
        fallback_text: resolution.unmatched? ? resolution.fallback_text : nil
      )
    rescue StandardError => e
      item&.update(status: "failed", error_message: e.message)

      notifier.broadcast(
        job_id,
        event: "document_processed",
        status: "error",
        filename: file_path ? File.basename(file_path) : nil,
        message: e.message
      )
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

    def compute_textract_confidence(ocr_lines:, recipient_names:, metadata:)
      {
        recipient: confidence_for_values(ocr_lines, recipient_names),
        date: confidence_for_values(ocr_lines, date_candidates(metadata[:date])),
        company: confidence_for_values(ocr_lines, [metadata[:company]]),
        department: confidence_for_values(ocr_lines, [metadata[:department]])
      }
    end

    def build_global_confidence(llm_confidence, textract_confidence)
      {
        recipient: merge_confidence(llm_confidence[:recipient], textract_confidence[:recipient]),
        date: merge_confidence(llm_confidence[:date], textract_confidence[:date]),
        company: merge_confidence(llm_confidence[:company], textract_confidence[:company]),
        department: merge_confidence(llm_confidence[:department], textract_confidence[:department])
      }
    end

    def merge_confidence(llm_value, textract_value)
      llm = llm_value.nil? ? 0.0 : llm_value.to_f
      textract = textract_value.nil? ? 0.0 : textract_value.to_f

      ((llm + textract) / 2.0).round(3)
    end

    def confidence_for_values(ocr_lines, values)
      normalized_values = Array(values).filter_map { |value| normalize_match_key(value) }.uniq
      return 0.0 if normalized_values.empty?

      matches = Array(ocr_lines).filter_map do |line|
        text = normalize_match_key(line[:text])
        next if text.blank?

        matched = normalized_values.any? { |value| text.include?(value) || value.include?(text) }
        next unless matched

        confidence = line[:confidence]
        next if confidence.nil?

        [[confidence.to_f / 100.0, 0.0].max, 1.0].min
      end

      return 0.0 if matches.empty?

      (matches.sum / matches.size.to_f).round(3)
    end

    def normalize_match_key(value)
      value.to_s
        .unicode_normalize(:nfd)
        .gsub(/\p{Mn}/, "")
        .downcase
        .gsub(/[^a-z0-9]/, "")
        .presence
    end

    def date_candidates(value)
      raw = value.to_s.strip
      return [] if raw.blank?

      candidates = [raw]

      if raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        year, month, day = raw.split("-")
        candidates << "#{day}/#{month}/#{year}"
        candidates << "#{day}-#{month}-#{year}"
      end

      candidates.uniq
    end
  end
end