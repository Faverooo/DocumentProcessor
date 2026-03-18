class DropProcessedDocuments < ActiveRecord::Migration[8.1]
  def change
    # Drop table if exists to support idempotent runs in different environments.
    drop_table :processed_documents, if_exists: true
  end
end
