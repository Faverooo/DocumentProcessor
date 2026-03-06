class DocumentProcessingChannel < ApplicationCable::Channel
  def subscribed
    stream_from "document_processing:#{params[:job_id]}"
  end
end
