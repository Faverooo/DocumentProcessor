module DocumentProcessing
  module Lookups
    class CompaniesFetcher
      # Restituisce un array di nomi azienda unici, ordinati.
      # Aggrega valori da UploadedDocument.override_company e da ExtractedDocument.metadata["company"].
      def call
        companies = UploadedDocument.where.not(override_company: [nil, ""]).pluck(:override_company)

        # metadata e JSON; estraiamo il campo company se presente
        meta_companies = ExtractedDocument.pluck(:metadata).map do |m|
          next unless m.is_a?(Hash)
          m["company"]
        end.compact

        (companies + meta_companies).map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort
      end
    end
  end
end