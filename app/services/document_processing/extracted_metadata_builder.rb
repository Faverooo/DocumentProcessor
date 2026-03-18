module DocumentProcessing
  class ExtractedMetadataBuilder
    def initialize(metadata:, uploaded_document: nil)
      @metadata = metadata || {}
      @uploaded_document = uploaded_document
    end

    def build
      {
        company: uploaded_document&.override_company.presence || metadata[:company],
        department: uploaded_document&.override_department.presence || metadata[:department],
        type: (uploaded_document&.category.presence || metadata[:type].presence),
        date: uploaded_document&.competence_period.presence || metadata[:date],
        reason: metadata[:reason],
        competence: (uploaded_document&.competence_period.presence || metadata[:competence])
      }
    end

    private

    attr_reader :metadata, :uploaded_document
  end
end
