require "test_helper"

class ProcessGenericFileTest < ActiveSupport::TestCase
  class FakeNotifier
    attr_reader :events

    def initialize
      @events = []
    end

    def broadcast(job_id, payload)
      @events << [job_id, payload]
    end
  end

  class FakeResolution
    def initialize(employee)
      @employee = employee
    end

    def matched?
      @employee.present?
    end

    attr_reader :employee
  end

  class FakeRecipientResolver
    def resolve(recipient_names:, raw_text:)
      employee = Employee.new(id: 10, name: recipient_names.first, email: "person@example.com", employee_code: "E10")
      FakeResolution.new(employee)
    end
  end

  class FakeContainer
    attr_reader :notifier

    def initialize
      @notifier = FakeNotifier.new
    end

    def recipient_resolver
      FakeRecipientResolver.new
    end
  end

  test "csv processing emits uniform document_processed payload" do
    uploaded_document = UploadedDocument.create!(
      original_filename: "records.csv",
      storage_path: "/tmp/records.csv",
      page_count: 1,
      checksum: "csv-checksum-1"
    )

    run = ProcessingRun.create!(
      job_id: "job-csv-1",
      status: "queued",
      original_filename: uploaded_document.original_filename,
      uploaded_document: uploaded_document
    )

    csv = Tempfile.new(["rows", ".csv"])
    csv.write("recipient,amount\nMario Rossi,100\n")
    csv.rewind

    container = FakeContainer.new

    DocumentProcessing::ProcessGenericFile.new(container: container).call(
      file_path: csv.path,
      job_id: run.job_id,
      uploaded_document_id: uploaded_document.id,
      file_kind: "csv"
    )

    document_event = container.notifier.events.find { |_job_id, payload| payload[:event] == "document_processed" }
    completed_event = container.notifier.events.find { |_job_id, payload| payload[:event] == "processing_completed" }

    assert_not_nil document_event
    assert_not_nil completed_event

    payload = document_event[1]
    expected_keys = %i[event status filename ocr_text recipient extracted_document_data extracted_confidence matched_recipient extracted_document_id document_index total_documents message]
    assert_equal expected_keys.sort, payload.keys.sort
    assert_equal "success", payload[:status]
    assert_equal "records.csv", payload[:filename]
    assert_nil payload[:ocr_text]
    assert_equal "Mario Rossi", payload[:recipient]
    assert_equal 1, payload[:document_index]
    assert_equal 1, payload[:total_documents]
  ensure
    csv.close! if csv
  end

  test "image processing emits uniform document_processed payload" do
    uploaded_document = UploadedDocument.create!(
      original_filename: "scan.png",
      storage_path: "/tmp/scan.png",
      page_count: 1,
      checksum: "img-checksum-1"
    )

    run = ProcessingRun.create!(
      job_id: "job-img-1",
      status: "queued",
      original_filename: uploaded_document.original_filename,
      uploaded_document: uploaded_document
    )

    employee = Employee.create!(name: "Mario Rossi", email: "mario@example.com", employee_code: "E1")

    fake_image_processor = Object.new
    fake_image_processor.define_singleton_method(:extract) do |_path|
      {
        ocr_text: "Mario Rossi fattura",
        metadata: { "type" => "fattura" },
        confidence: { "recipient" => 0.9 },
        recipient: "Mario Rossi",
        employee: employee
      }
    end

    container = FakeContainer.new

    DocumentProcessing::ImageProcessor.stub(:new, fake_image_processor) do
      DocumentProcessing::ProcessGenericFile.new(container: container).call(
        file_path: "/tmp/scan.png",
        job_id: run.job_id,
        uploaded_document_id: uploaded_document.id,
        file_kind: "image"
      )
    end

    document_event = container.notifier.events.find { |_job_id, payload| payload[:event] == "document_processed" }
    completed_event = container.notifier.events.find { |_job_id, payload| payload[:event] == "processing_completed" }

    assert_not_nil document_event
    assert_not_nil completed_event

    payload = document_event[1]
    expected_keys = %i[event status filename ocr_text recipient extracted_document_data extracted_confidence matched_recipient extracted_document_id document_index total_documents message]
    assert_equal expected_keys.sort, payload.keys.sort
    assert_equal "success", payload[:status]
    assert_equal "scan.png", payload[:filename]
    assert_equal "Mario Rossi fattura", payload[:ocr_text]
    assert_equal "Mario Rossi", payload[:recipient]
    assert_equal 1, payload[:document_index]
    assert_equal 1, payload[:total_documents]
    assert_equal "mario@example.com", payload[:matched_recipient][:email]
  end
end
