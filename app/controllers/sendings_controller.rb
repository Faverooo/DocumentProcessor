class SendingsController < ApplicationController
  # GET /sendings
  def index
    sendings = Sending.includes(:recipient, :extracted_document).order(created_at: :desc)
    render json: { sendings: sendings.map { |s| sending_representation(s) } }
  end

  # POST /sendings
  # Params: extracted_document_id, recipient_id, sent_at, subject (opt), body (opt), template_id (opt)
  def create
    sd_params = sending_params
    
    result = DocumentProcessing::Sendings::CreateSending.new(
      extracted_document_id: sd_params[:extracted_document_id],
      recipient_id: sd_params[:recipient_id],
      sent_at: sd_params[:sent_at],
      subject: sd_params[:subject],
      body: sd_params[:body],
      template_id: sd_params[:template_id]
    ).call

    if result.success?
      render json: { status: "ok", sending: sending_representation(result.result[:sending]) }, status: :created
    else
      status_code = result.result[:status] || :unprocessable_entity
      render json: { status: "error", message: result.result[:error] }, status: status_code
    end
  end

  private

  def sending_params
    params.permit(:extracted_document_id, :recipient_id, :sent_at, :subject, :body, :template_id)
  end

  def sending_representation(s)
    {
      id: s.id,
      extracted_document_id: s.extracted_document_id,
      recipient: { id: s.recipient.id, name: s.recipient.name, email: s.recipient.email, employee_code: s.recipient.employee_code },
      subject: s.subject,
      body: s.body,
      template_id: s.template_id,
      sent_at: s.sent_at,
      created_at: s.created_at
    }
  end
end
