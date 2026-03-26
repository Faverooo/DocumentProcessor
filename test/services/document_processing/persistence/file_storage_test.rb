require "test_helper"

class DocumentProcessing::Persistence::FileStorageTest < ActiveSupport::TestCase
  test "exist and delete work on filesystem" do
    file = Tempfile.new("storage-test")
    path = file.path
    file.write("x")
    file.close

    storage = DocumentProcessing::Persistence::FileStorage.new

    assert storage.exist?(path)
    storage.delete(path)
    assert_not storage.exist?(path)
  end

  test "expanded returns absolute path" do
    storage = DocumentProcessing::Persistence::FileStorage.new

    path = storage.expanded(".")

    assert Pathname.new(path).absolute?
  end
end
