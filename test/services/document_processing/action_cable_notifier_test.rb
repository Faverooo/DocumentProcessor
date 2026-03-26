require "test_helper"

class ActionCableNotifierTest < ActiveSupport::TestCase
  class FakeBroadcaster
    attr_reader :calls

    def initialize
      @calls = []
    end

    def broadcast(channel, payload)
      @calls << [channel, payload]
    end
  end

  test "broadcast sends payload on job channel" do
    broadcaster = FakeBroadcaster.new
    notifier = DocumentProcessing::ActionCableNotifier.new(broadcaster: broadcaster)

    notifier.broadcast("job-1", { event: "ok" })

    assert_equal 1, broadcaster.calls.size
    assert_equal "document_processing:job-1", broadcaster.calls.first[0]
    assert_equal({ event: "ok" }, broadcaster.calls.first[1])
  end
end
