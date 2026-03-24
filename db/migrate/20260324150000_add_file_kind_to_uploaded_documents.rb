class AddFileKindToUploadedDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :uploaded_documents, :file_kind, :string unless column_exists?(:uploaded_documents, :file_kind)
    add_index :uploaded_documents, :file_kind unless index_exists?(:uploaded_documents, :file_kind)
  end
end
