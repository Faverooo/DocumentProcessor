module DocumentProcessing
  module Sendings
    class CreateSending
      attr_reader :result

      def initialize(extracted_document_id:, recipient_id:, sent_at:, subject: nil, body: nil, template_id: nil)
        @extracted_document_id = extracted_document_id
        @recipient_id = recipient_id
        @sent_at = sent_at
        @subject = subject
        @body = body
        @template_id = template_id
        @result = {}
      end

      def call
        validate_inputs
        return self if @result[:error]

        sending = build_sending
        return self unless save_sending(sending)

        @result = { success: true, sending: sending }
        self
      end

      def success?
        @result[:success] == true
      end

      private

      def validate_inputs
        return unless @extracted_document_id.blank? || @recipient_id.blank? || @sent_at.blank?
        @result = { error: "extracted_document_id, recipient_id, sent_at sono obbligatori", status: :bad_request }
      end

      def build_sending
        sending = Sending.new(
          extracted_document_id: @extracted_document_id,
          recipient_id: @recipient_id,
          sent_at: @sent_at,
          subject: @subject,
          body: @body,
          template_id: @template_id
        )

        # If a template is selected and explicit values are missing, inherit them.
        if sending.template_id.present? && sending.subject.blank?
          template = Template.find_by(id: sending.template_id)
          sending.subject = template.subject if template
          sending.body = template.body if template && sending.body.blank?
        end

        sending
      end

      def save_sending(sending)
        ActiveRecord::Base.transaction do
          unless sending.save
            @result = { error: sending.errors.full_messages.join(", "), status: :unprocessable_entity }
            raise ActiveRecord::Rollback
          end

          if sending.extracted_document_id.present?
            extracted = ExtractedDocument.find_by(id: sending.extracted_document_id)
            if extracted
              unless extracted.update(status: "sent")
                @result = { error: extracted.errors.full_messages.join(", "), status: :unprocessable_entity }
                raise ActiveRecord::Rollback
              end
            end
          end
        end

        return false if @result[:error]
        true
      end
    end
  end
end