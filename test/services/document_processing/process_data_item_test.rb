require "test_helper"

class ProcessDataItemTest < ActiveSupport::TestCase
  class FakeRepository
    attr_reader :calls

    def initialize(run:, item:, extracted_document:)
      @run = run
      @item = item
      @extracted_document = extracted_document
      @calls = []
    end

    def find_run_by_job_id(_job_id)
      @run
    end

    def find_processing_item(_id)
      @item
    end

    def find_extracted_document(_id)
      @extracted_document
    end

    def terminal_item?(_item)
      false
    end

    def mark_item_in_progress!(_item)
      @calls << :item_in_progress
    end

    def mark_extracted_document_in_progress!(_doc)
      @calls << :doc_in_progress
    end

    def mark_item_done!(item:, resolution:)
      @calls << :item_done
    end

    def mark_extracted_document_done!(**kwargs)
      @calls << :doc_done
    end

    def mark_item_failed(item:, error_message:)
      @calls << :item_failed
    end

    def mark_extracted_document_failed(extracted_document:, error_message:)
      @calls << :doc_failed
    end

    def update_progress!(_run)
      { completed: true }
    end
  end

  class FakeNotifier
    attr_reader :events

    def initialize
      @events = []
    end

    def broadcast(job_id, payload)
      @events << [job_id, payload]
    end
  end

  class FakeFileStorage
    def exist?(_path)
      true
    end

    def delete(_path)
      true
    end
  end

  class FakeResolution
    attr_reader :employee

    def initialize(employee)
      @employee = employee
    end

    def matched?
      true
    end
  end

  class FakeMetadataBuilder
    def initialize(metadata:, uploaded_document:)
      @metadata = metadata
    end

    def build
      @metadata
    end
  end

  class FakeConfidenceCalculator
    def initialize(**kwargs)
    end

    def global_confidence
      { recipient: 0.9 }
    end
  end

  class FakeContainer
    attr_reader :data_item_repository, :notifier, :file_storage

    def initialize(repo:, notifier:, file_storage:, employee:)
      @data_item_repository = repo
      @notifier = notifier
      @file_storage = file_storage
      @employee = employee
    end

    def ocr_service
      Object.new.tap do |svc|
        svc.define_singleton_method(:full_ocr) { |_path| { text: "Mario Rossi", lines: [{ text: "Mario Rossi", confidence: 95 }] } }
      end
    end

    def data_extractor
      Object.new.tap do |svc|
        svc.define_singleton_method(:extract) do |_text|
          { recipients: ["Mario Rossi"], metadata: { company: "ACME" }, llm_confidence: { recipient: 0.8 } }
        end
      end
    end

    def recipient_resolver
      Object.new.tap do |svc|
        employee = @employee
        svc.define_singleton_method(:resolve) { |recipient_names:, raw_text:| FakeResolution.new(employee) }
      end
    end

    def extracted_metadata_builder(**kwargs)
      FakeMetadataBuilder.new(**kwargs)
    end

    def confidence_calculator(**kwargs)
      FakeConfidenceCalculator.new(**kwargs)
    end
  end

  test "processes item and broadcasts success plus completion" do
    uploaded = UploadedDocument.create!(original_filename: "x.pdf", storage_path: "/tmp/x", page_count: 1, checksum: "pdi-1", file_kind: "pdf")
    extracted = ExtractedDocument.create!(uploaded_document: uploaded, sequence: 1, page_start: 1, page_end: 1)
    employee = Employee.create!(name: "Mario", email: "mario@test.it", employee_code: "EMP-PDI")

    run = ProcessingRun.create!(job_id: "job-pdi", total_documents: 1)
    item = ProcessingItem.create!(processing_run: run, sequence: 1, filename: "x.pdf", extracted_document: extracted)

    repo = FakeRepository.new(run: run, item: item, extracted_document: extracted)
    notifier = FakeNotifier.new
    file_storage = FakeFileStorage.new
    container = FakeContainer.new(repo: repo, notifier: notifier, file_storage: file_storage, employee: employee)

    DocumentProcessing::ProcessDataItem.new(container: container).call(
      file_path: "/tmp/x.pdf",
      job_id: "job-pdi",
      processing_item_id: item.id,
      extracted_document_id: extracted.id
    )

    assert_includes repo.calls, :item_done
    assert_includes repo.calls, :doc_done
    assert_equal 2, notifier.events.size
    assert_equal "document_processed", notifier.events[0][1][:event]
    assert_equal "processing_completed", notifier.events[1][1][:event]
  end
end
