class AddChecksumToUploadedDocuments < ActiveRecord::Migration[6.1]
  def change
    add_column :uploaded_documents, :checksum, :string
    add_index :uploaded_documents, :checksum, unique: true
  end
end
