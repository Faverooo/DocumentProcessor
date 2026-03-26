require "test_helper"

class ContainerTest < ActiveSupport::TestCase
  class FakeOcr
    attr_reader :client

    def initialize(textract_client:)
      @client = textract_client
    end
  end

  class FakeExtractor
    attr_reader :llm

    def initialize(llm_service:)
      @llm = llm_service
    end
  end

  class FakeLlm
    attr_reader :client

    def initialize(bedrock_client:)
      @client = bedrock_client
    end
  end

  class FakeNotifier
    attr_reader :calls

    def initialize(broadcaster:)
      @broadcaster = broadcaster
      @calls = []
    end

    def broadcast(job_id, payload)
      @calls << [job_id, payload]
    end
  end

  class FakeFileStorage
    def exist?(_path)
      false
    end
  end

  test "builds services with injected dependencies" do
    textract = Object.new
    bedrock = Object.new

    container = DocumentProcessing::Container.new(
      ocr_service_class: FakeOcr,
      data_extractor_class: FakeExtractor,
      llm_service_class: FakeLlm,
      notifier_class: FakeNotifier,
      file_storage_class: FakeFileStorage,
      textract_client: textract,
      bedrock_client: bedrock
    )

    assert_same textract, container.ocr_service.client
    assert_same bedrock, container.data_extractor.llm.client
    assert_instance_of FakeFileStorage, container.file_storage
  end

  test "broadcast delegates to notifier" do
    container = DocumentProcessing::Container.new(notifier_class: FakeNotifier)

    container.broadcast("job-x", { event: "ping" })

    assert_equal 1, container.notifier.calls.size
    assert_equal "job-x", container.notifier.calls.first[0]
  end
end
