module DocumentProcessing
  class DataExtractor
    def initialize(llm_service:)
      @llm_service = llm_service
    end

    def extract(text)
      return empty_document_data if text.to_s.strip.blank?

      parsed = llm_service.extract_document_data(text)

      recipients = Array(parsed["recipients"]).filter_map do |entry|
        normalize_name(entry["name"] || entry[:name])
      end

      {
        recipients: recipients.uniq,
        metadata: extract_metadata(parsed),
        llm_confidence: extract_llm_confidence(parsed)
      }
    rescue StandardError => error
      Rails.logger.error("Errore estrazione dati documento LLM: #{error.message}")
      empty_document_data
    end

    private

    attr_reader :llm_service

    def normalize_name(name)
      cleaned = name.to_s.gsub(/\s+/, " ").strip
      return nil if cleaned.blank? || cleaned.length < 3

      cleaned
    end

    def extract_metadata(parsed)
      document_data = parsed["document"] || parsed[:document] || {}

      {
        date: normalize_field(
          document_data["date"] ||
          document_data[:date] ||
          parsed["date"] ||
          parsed[:date]
        ),
        company: normalize_field(
          document_data["company"] ||
          document_data[:company] ||
          parsed["company"] ||
          parsed[:company]
        ),
        department: normalize_field(
          document_data["department"] ||
          document_data[:department] ||
          parsed["department"] ||
          parsed[:department]
        ),
        type: normalize_field(
          document_data["type"] ||
          document_data[:type] ||
          parsed["type"] ||
          parsed[:type]
        ),
        reason: normalize_field(
          document_data["reason"] ||
          document_data[:reason] ||
          parsed["reason"] ||
          parsed[:reason] ||
          document_data["causale"] ||
          document_data[:causale] ||
          parsed["causale"] ||
          parsed[:causale]
        ),
        competence: normalize_field(
          document_data["competence"] ||
          document_data[:competence] ||
          parsed["competence"] ||
          parsed[:competence] ||
          document_data["competenza"] ||
          document_data[:competenza] ||
          parsed["competenza"] ||
          parsed[:competenza]
        )
      }
    end

    def extract_llm_confidence(parsed)
      confidence = parsed["confidence"] || parsed[:confidence] || {}

      {
        recipient: normalize_confidence(confidence["recipient"] || confidence[:recipient]),
        date: normalize_confidence(confidence["date"] || confidence[:date]),
        company: normalize_confidence(confidence["company"] || confidence[:company]),
        department: normalize_confidence(confidence["department"] || confidence[:department]),
        type: normalize_confidence(confidence["type"] || confidence[:type]),
        reason: normalize_confidence(confidence["reason"] || confidence[:reason]),
        competence: normalize_confidence(confidence["competence"] || confidence[:competence])
      }
    end

    def normalize_field(value)
      cleaned = value.to_s.gsub(/\s+/, " ").strip
      cleaned.presence
    end

    def normalize_confidence(value)
      return 0.0 if value.nil?

      numeric = value.to_f
      return 0.0 if numeric.nan?

      [[numeric, 0.0].max, 1.0].min.round(3)
    end

    def empty_document_data
      {
        recipients: [],
        metadata: {
          date: nil,
          company: nil,
          department: nil,
          type: nil,
          reason: nil,
          competence: nil
        },
        llm_confidence: {
          recipient: 0.0,
          date: 0.0,
          company: 0.0,
          department: 0.0,
          type: 0.0,
          reason: 0.0,
          competence: 0.0
        }
      }
    end
  end
end
