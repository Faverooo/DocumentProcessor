class CreateExtractedDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :extracted_documents do |t|
      t.references :uploaded_document, null: false, foreign_key: true
      t.integer :sequence, null: false
      t.integer :page_start, null: false
      t.integer :page_end, null: false
      t.string :status, null: false, default: "queued"
      t.json :metadata, null: false, default: {}
      t.json :recipients, null: false, default: []
      t.json :confidence, null: false, default: {}
      t.string :recipient_name
      t.references :matched_employee, null: true, foreign_key: { to_table: :employees }
      t.text :error_message
      t.datetime :processed_at

      t.timestamps
    end

    add_index :extracted_documents, [ :uploaded_document_id, :sequence ], unique: true
    add_index :extracted_documents, :status
  end
end