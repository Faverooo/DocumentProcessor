require "test_helper"

class ImageProcessorTest < ActiveSupport::TestCase
  class FakeOcrService
    def full_ocr(_file_path)
      { text: "Mario Rossi fattura 123" }
    end
  end

  class FakeDataExtractor
    def extract(_text)
      {
        recipients: ["Mario Rossi"],
        metadata: { "type" => "fattura" },
        llm_confidence: { "recipient" => 0.9 }
      }
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
      employee = Employee.new(id: 1, name: recipient_names.first, email: "mario@example.com", employee_code: "E1")
      FakeResolution.new(employee)
    end
  end

  class FakeContainer
    def ocr_service
      FakeOcrService.new
    end

    def data_extractor
      FakeDataExtractor.new
    end

    def recipient_resolver
      FakeRecipientResolver.new
    end
  end

  test "extract returns normalized payload" do
    processor = DocumentProcessing::ImageProcessor.new(container: FakeContainer.new)

    result = processor.extract("/tmp/fake.png")

    assert_equal "Mario Rossi", result[:recipient]
    assert_equal "fattura", result[:metadata]["type"]
    assert_equal 0.9, result[:confidence]["recipient"]
    assert_equal "mario@example.com", result[:employee].email
  end
end
