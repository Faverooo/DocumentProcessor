class AddDocumentMetadataFields < ActiveRecord::Migration[8.1]
  def up
    add_column :uploaded_documents, :category, :string unless column_exists?(:uploaded_documents, :category)
    add_column :uploaded_documents, :override_company, :string unless column_exists?(:uploaded_documents, :override_company)
    add_column :uploaded_documents, :override_department, :string unless column_exists?(:uploaded_documents, :override_department)
    add_column :uploaded_documents, :competence_period, :string unless column_exists?(:uploaded_documents, :competence_period)

    add_column :extracted_documents, :fallback_text, :text unless column_exists?(:extracted_documents, :fallback_text)
    add_column :extracted_documents, :document_type, :string unless column_exists?(:extracted_documents, :document_type)
    add_column :extracted_documents, :process_time_seconds, :float unless column_exists?(:extracted_documents, :process_time_seconds)
  end

  def down
    remove_column :extracted_documents, :process_time_seconds if column_exists?(:extracted_documents, :process_time_seconds)
    remove_column :extracted_documents, :document_type if column_exists?(:extracted_documents, :document_type)
    remove_column :extracted_documents, :fallback_text if column_exists?(:extracted_documents, :fallback_text)

    remove_column :uploaded_documents, :competence_period if column_exists?(:uploaded_documents, :competence_period)
    remove_column :uploaded_documents, :override_department if column_exists?(:uploaded_documents, :override_department)
    remove_column :uploaded_documents, :override_company if column_exists?(:uploaded_documents, :override_company)
    remove_column :uploaded_documents, :category if column_exists?(:uploaded_documents, :category)
  end
end
