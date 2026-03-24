module DocumentProcessing
  class ImageProcessor
    def initialize(container:)
      @container = container
    end

    # Pure extraction for images: no DB writes, no broadcast.
    def extract(file_path)
      ocr_result = container.ocr_service.full_ocr(file_path)
      full_text = ocr_result[:text]

      extracted = container.data_extractor.extract(full_text)
      recipient_names = extracted[:recipients]
      recipient = Array(recipient_names).compact.first
      resolution = container.recipient_resolver.resolve(recipient_names: recipient_names, raw_text: full_text)

      {
        ocr_text: full_text,
        metadata: extracted[:metadata],
        confidence: extracted[:llm_confidence],
        recipient: recipient,
        employee: resolution.matched? ? resolution.employee : nil
      }
    end

    private

    attr_reader :container
  end
end
