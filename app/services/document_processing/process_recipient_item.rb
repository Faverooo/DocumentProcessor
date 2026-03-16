module DocumentProcessing
  class ProcessRecipientItem
    def initialize(container:)
      @container = container
    end

    def call(file_path:, job_id:, processing_item_id: nil)
      run = ProcessingRun.find_by(job_id: job_id)
      item = processing_item_id ? ProcessingItem.find_by(id: processing_item_id) : nil
      return if already_terminal_item?(item)

      mark_item_in_progress(item)

      full_text = container.ocr_service.full_ocr(file_path)
      extraction = container.recipient_extractor.extract(full_text)
      recipient_names = extraction[:recipients]
      extracted_document_data = extraction[:metadata]
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
    ensure # lo fa sempre, anche in caso di errori, per evitare di lasciare file temporanei
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
  end
end