module DocumentProcessing
  class ImageProcessor
    def initialize(ocr_service:, data_extractor:, recipient_resolver:)
      @ocr_service = ocr_service
      @data_extractor = data_extractor
      @recipient_resolver = recipient_resolver
    end

    # Pure extraction for images: no DB writes, no broadcast.
    def extract(file_path)
      ocr_result = ocr_service.full_ocr(file_path)
      full_text = ocr_result[:text]
      ocr_lines = ocr_result[:lines]

      extracted = data_extractor.extract(full_text)
      recipient_names = extracted[:recipients]
      recipient = Array(recipient_names).compact.first
      resolution = recipient_resolver.resolve(recipient_names: recipient_names, raw_text: full_text)

      {
        ocr_text: full_text,
        ocr_lines: ocr_lines,
        metadata: extracted[:metadata],
        confidence: extracted[:llm_confidence],
        recipient: recipient,
        employee: resolution.matched? ? resolution.employee : nil
      }
    end

    private

    attr_reader :ocr_service, :data_extractor, :recipient_resolver
  end
end
