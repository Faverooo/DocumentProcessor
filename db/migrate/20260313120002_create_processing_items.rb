class CreateProcessingItems < ActiveRecord::Migration[8.1]
  def change
    create_table :processing_items do |t|
      t.references :processing_run, null: false, foreign_key: true
      t.integer :sequence, null: false
      t.string :filename, null: false
      t.string :status, null: false, default: "queued"
      t.string :recipient_name
      t.references :matched_employee, null: true, foreign_key: { to_table: :employees }
      t.text :error_message

      t.timestamps
    end

    add_index :processing_items, [:processing_run_id, :sequence], unique: true
    add_index :processing_items, :status
  end
end
