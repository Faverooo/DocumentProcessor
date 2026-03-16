module DocumentProcessing
  class ActionCableNotifier
    def initialize(broadcaster: ActionCable.server)
      @broadcaster = broadcaster
    end

    def broadcast(job_id, data)
      @broadcaster.broadcast("document_processing:#{job_id}", data)
    end
  end
end