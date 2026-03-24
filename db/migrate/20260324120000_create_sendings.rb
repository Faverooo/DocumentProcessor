class CreateSendings < ActiveRecord::Migration[8.1]
  def change
    create_table :sendings do |t|
      t.integer :extracted_document_id, null: false
      t.integer :recipient_id, null: false
      t.datetime :sent_at, null: false

      t.timestamps
    end

    add_index :sendings, :extracted_document_id
    add_index :sendings, :recipient_id

    add_foreign_key :sendings, :extracted_documents, column: :extracted_document_id
    add_foreign_key :sendings, :employees, column: :recipient_id
  end
end
