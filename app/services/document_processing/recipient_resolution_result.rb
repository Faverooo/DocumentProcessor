module DocumentProcessing
  class RecipientResolutionResult
    STATUSES = %w[matched unmatched empty].freeze

    attr_reader :status, :employee, :fallback_text, :score, :matched_term

    def initialize(status:, employee: nil, fallback_text: nil, score: nil, matched_term: nil)
      normalized_status = status.to_s
      raise ArgumentError, "Invalid status: #{status}" unless STATUSES.include?(normalized_status)

      @status = normalized_status
      @employee = employee
      @fallback_text = fallback_text # È il testo “di ripiego” da mostrare quando non trovi un dipendente nel DB.
      @score = score
      @matched_term = matched_term # È il termine normalizzato usato dal motore di matching per confrontare col DB.
    end

    def matched?
      status == "matched"
    end

    def unmatched?
      status == "unmatched"
    end

    def empty?
      status == "empty"
    end
  
  end
end