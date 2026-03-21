class RenameFallbackTextToRawRecipientAndRemoveRecipientName < ActiveRecord::Migration[8.1]
  def up
    if column_exists?(:extracted_documents, :fallback_text)
      rename_column :extracted_documents, :fallback_text, :raw_recipient
    end

    if column_exists?(:extracted_documents, :recipient_name)
      remove_column :extracted_documents, :recipient_name
    end

    if column_exists?(:processing_items, :recipient_name)
      remove_column :processing_items, :recipient_name
    end
  end

  def down
    unless column_exists?(:extracted_documents, :fallback_text)
      if column_exists?(:extracted_documents, :raw_recipient)
        rename_column :extracted_documents, :raw_recipient, :fallback_text
      else
        add_column :extracted_documents, :fallback_text, :text
      end
    end

    unless column_exists?(:extracted_documents, :recipient_name)
      add_column :extracted_documents, :recipient_name, :string
    end

    unless column_exists?(:processing_items, :recipient_name)
      add_column :processing_items, :recipient_name, :string
    end
  end
end
