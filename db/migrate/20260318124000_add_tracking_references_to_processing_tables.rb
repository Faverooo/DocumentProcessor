class AddTrackingReferencesToProcessingTables < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:processing_runs, :uploaded_document_id)
      add_reference :processing_runs, :uploaded_document, foreign_key: true, index: true
    end

    unless column_exists?(:processing_items, :extracted_document_id)
      add_reference :processing_items, :extracted_document, foreign_key: true, index: true
    end
  end

  def down
    if column_exists?(:processing_items, :extracted_document_id)
      remove_reference :processing_items, :extracted_document, foreign_key: true
    end

    if column_exists?(:processing_runs, :uploaded_document_id)
      remove_reference :processing_runs, :uploaded_document, foreign_key: true
    end
  end
end
