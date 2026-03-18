class RemoveDocumentTypeFromExtractedDocuments < ActiveRecord::Migration[8.1]
  def change
    remove_column :extracted_documents, :document_type, :string if column_exists?(:extracted_documents, :document_type)
  end
end
