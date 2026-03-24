module Lookups
  class UsersFetcher
    # Restituisce uno scope/array di Employee.
    # Se viene passato `company`, filtra gli utenti che sono stati matchati in documenti
    # appartenenti a quella azienda (override_company) o il cui ExtractedDocument.metadata["company"] corrisponde.
    def call(company: nil)
      return Employee.all if company.nil? || company.to_s.strip.empty?

      company = company.to_s.strip

      # Trova matched_employee_id da extracted_documents dove
      # uploaded_documents.override_company == company oppure metadata['company'] == company
      ids_from_uploaded = UploadedDocument.where(override_company: company).joins(:extracted_documents).pluck("extracted_documents.matched_employee_id")

      ids_from_metadata = ExtractedDocument.pluck(:metadata, :matched_employee_id).map do |metadata, mid|
        next unless metadata.is_a?(Hash)
        mid if metadata["company"].to_s.strip == company
      end.compact

      matched_ids = (ids_from_uploaded + ids_from_metadata).compact.uniq

      Employee.where(id: matched_ids)
    end
  end
end
