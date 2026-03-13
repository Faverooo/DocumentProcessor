class CreateProcessingRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :processing_runs do |t|
      t.string :job_id, null: false
      t.string :status, null: false, default: "queued"
      t.string :original_filename
      t.integer :total_documents, null: false, default: 0
      t.integer :processed_documents, null: false, default: 0
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :processing_runs, :job_id, unique: true
    add_index :processing_runs, :status
  end
end
