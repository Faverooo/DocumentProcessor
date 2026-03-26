module DocumentProcessing
  module Persistence
    class DbManager
      def initialize(data_item_repository:, recipient_resolver:)
        @repo = data_item_repository
        @recipient_resolver = recipient_resolver
      end

      # Restituisce tutti i documenti caricati (minimo payload)
      # => [{ id:, original_filename:, page_count:, file_kind:, created_at: }, ...]
      def uploaded_documents_list
        UploadedDocument.order(created_at: :desc).pluck(:id, :original_filename, :page_count, :file_kind, :created_at).map do |id, name, pages, kind, ts|
          { id: id, original_filename: name, page_count: pages, file_kind: kind, created_at: ts }
        end
      end

      # Aggiorna campi selettivi dentro extracted_document.metadata
      # metadata_updates: hash di chiavi => valori (shallow)
      # Imposta confidence[key] = 100 per ogni chiave aggiornata
      # Ritorna l'oggetto ExtractedDocument aggiornato
      def update_extracted_metadata(extracted_document_id:, metadata_updates: {})
        raise ArgumentError, "metadata_updates must be a Hash" unless metadata_updates.is_a?(Hash)

        extracted = @repo.find_extracted_document(extracted_document_id)
        raise ActiveRecord::RecordNotFound, "ExtractedDocument #{extracted_document_id} not found" unless extracted

        extracted.with_lock do
          current_meta = extracted.metadata || {}
          new_meta = current_meta.merge(metadata_updates)

          current_conf = extracted.confidence || {}
          metadata_updates.each_key do |k|
            current_conf[k.to_s] = 100
          end

          # Re-resolve recipient if the metadata update contains recipient-related fields
          # Decide single recipient: prefer explicit `raw_recipient` or `recipient` in metadata, otherwise first element of `recipients`
          recipient = if new_meta.key?("raw_recipient") && new_meta["raw_recipient"].present?
            new_meta["raw_recipient"].to_s
          elsif new_meta.key?("recipient") && new_meta["recipient"].present?
            new_meta["recipient"].to_s
          elsif new_meta.key?("recipients") && new_meta["recipients"].is_a?(Array) && new_meta["recipients"].any?
            new_meta["recipients"].first.to_s
          else
            extracted.respond_to?(:recipient) ? extracted.recipient : (extracted.recipients.is_a?(Array) ? extracted.recipients.first : nil)
          end

          resolution = @recipient_resolver.resolve(recipient_names: [recipient].compact, raw_text: nil)

          extracted.update!(
            metadata: new_meta,
            confidence: current_conf,
            recipient: recipient,
            matched_employee: resolution.matched? ? resolution.employee : nil
          )
        end

        extracted.reload
      end
    end
  end
end
