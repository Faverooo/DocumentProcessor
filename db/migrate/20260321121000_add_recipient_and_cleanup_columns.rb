class AddRecipientAndCleanupColumns < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:extracted_documents, :recipient)
      add_column :extracted_documents, :recipient, :string
    end

    # Backfill `recipient` from `raw_recipient` if present, otherwise from `recipients` array first element
    say_with_time "Backfilling extracted_documents.recipient from raw_recipient/recipients" do
      ExtractedDocument.reset_column_information
      ExtractedDocument.find_each do |doc|
        next if doc.recipient.present?
        if doc.respond_to?(:raw_recipient) && doc.raw_recipient.present?
          doc.update_column(:recipient, doc.raw_recipient)
        elsif doc.respond_to?(:recipients) && doc.recipients.is_a?(Array) && doc.recipients.any?
          doc.update_column(:recipient, doc.recipients.first)
        end
      end
    end

    # Remove old columns
    if column_exists?(:extracted_documents, :raw_recipient)
      remove_column :extracted_documents, :raw_recipient
    end

    if column_exists?(:extracted_documents, :recipients)
      remove_column :extracted_documents, :recipients
    end
  end

  def down
    unless column_exists?(:extracted_documents, :raw_recipient)
      add_column :extracted_documents, :raw_recipient, :text
    end

    unless column_exists?(:extracted_documents, :recipients)
      add_column :extracted_documents, :recipients, :json, default: [], null: false
    end

    if column_exists?(:extracted_documents, :recipient)
      ExtractedDocument.reset_column_information
      ExtractedDocument.find_each do |doc|
        doc.update_column(:raw_recipient, doc.recipient) if doc.respond_to?(:recipient)
        doc.update_column(:recipients, [doc.recipient]) if doc.respond_to?(:recipient)
      end
      remove_column :extracted_documents, :recipient
    end
  end
end
