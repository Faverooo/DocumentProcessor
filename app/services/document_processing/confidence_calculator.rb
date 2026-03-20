module DocumentProcessing
  class ConfidenceCalculator
    def initialize(ocr_lines:, recipient_names:, metadata:, llm_confidence:, uploaded_document: nil)
      @ocr_lines = ocr_lines
      @recipient_names = recipient_names
      @metadata = metadata || {}
      @llm_confidence = llm_confidence || {}
      @uploaded_document = uploaded_document
    end

    def global_confidence
      textract = textract_confidence
      global = {
        recipient: merge_confidence(llm_confidence[:recipient], textract[:recipient]),
        date: merge_confidence(llm_confidence[:date], textract[:date]),
        company: merge_confidence(llm_confidence[:company], textract[:company]),
        department: merge_confidence(llm_confidence[:department], textract[:department]),
        type: llm_confidence_value(:type),
        reason: merge_confidence(llm_confidence[:reason], textract[:reason]),
        competence: merge_confidence(llm_confidence[:competence], textract[:competence])
      }

      apply_override_confidence(global)
    end

    private

    attr_reader :ocr_lines, :recipient_names, :metadata, :llm_confidence, :uploaded_document

    def llm_confidence_value(key)
      value = llm_confidence[key]
      return 0.0 if value.nil?

      [[value.to_f, 0.0].max, 1.0].min.round(3)
    end

    def textract_confidence
      {
        recipient: confidence_for_values(ocr_lines, recipient_names),
        date: confidence_for_values(ocr_lines, date_candidates(metadata[:date])),
        company: confidence_for_values(ocr_lines, [metadata[:company]]),
        department: confidence_for_values(ocr_lines, [metadata[:department]]),
        reason: confidence_for_values(ocr_lines, [metadata[:reason]]),
        competence: confidence_for_values(ocr_lines, [metadata[:competence]])
      }
    end

    def apply_override_confidence(global)
      return global if uploaded_document.nil?

      global[:company] = 1.0 if uploaded_document.override_company.present?
      global[:department] = 1.0 if uploaded_document.override_department.present?
      global[:type] = 1.0 if uploaded_document.category.present?
      global[:competence] = 1.0 if uploaded_document.competence_period.present?
      global
    end

    def merge_confidence(llm_value, textract_value)
      llm = llm_value.nil? ? 0.0 : llm_value.to_f
      textract = textract_value.nil? ? 0.0 : textract_value.to_f

      ((llm + textract) / 2.0).round(3)
    end

    def confidence_for_values(lines, values)
      normalized_values = Array(values).filter_map { |value| normalize_match_key(value) }.uniq
      return 0.0 if normalized_values.empty?

      matches = Array(lines).filter_map do |line|
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
