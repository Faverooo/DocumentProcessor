class CreateUploadedDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :uploaded_documents do |t|
      t.string :original_filename, null: false
      t.string :storage_path, null: false
      t.integer :page_count, null: false, default: 0

      t.timestamps
    end
  end
end