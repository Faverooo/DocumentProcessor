class CreateProcessedDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_documents do |t|
      t.string :filename
      t.string :status
      t.string :recipient_name
      t.references :employee, null: false, foreign_key: true

      t.timestamps
    end
  end
end
