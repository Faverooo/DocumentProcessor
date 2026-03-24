require "csv"

module DocumentProcessing
  class CSVProcessor
    # Pure parser: no DB writes, no broadcast.
    def parse(file_path)
      text = File.read(file_path)
      CSV.parse(text, headers: true).map(&:to_h)
    end

    # Pure extraction for CSV rows: extract and structure each row with LLM (like ImageProcessor for images).
    # No DB writes, no broadcast. Returns array of structured payloads (one per row).
    def extract_rows(file_path, container)
      rows = parse(file_path)

      rows.map do |raw_data|
        # Skip or handle empty rows
        next nil if raw_data.values.all? { |v| v.nil? || v.to_s.strip.empty? }

        # Concatenate row values into plain text for LLM extraction
        raw_text = raw_data.values.compact.join(" ").strip
        next nil if raw_text.empty?

        # Extract structured data via LLM
        extracted = container.data_extractor.extract(raw_text)
        recipient_names = extracted[:recipients]
        recipient = Array(recipient_names).compact.first
        confidence = extracted[:llm_confidence]
        metadata = extracted[:metadata]

        # Resolve recipient to employee
        resolution = container.recipient_resolver.resolve(recipient_names: recipient_names, raw_text: raw_text)

        {
          ocr_text: raw_text,
          metadata: metadata || raw_data,
          confidence: confidence || {},
          recipient: recipient,
          employee: resolution.matched? ? resolution.employee : nil
        }
      end.compact  # Remove nil entries for empty rows
    end
  end
end
