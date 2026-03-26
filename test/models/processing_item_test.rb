require "test_helper"

class ProcessingItemTest < ActiveSupport::TestCase
  test "is valid with required attributes" do
    item = ProcessingItem.new(
      processing_run: ProcessingRun.create!(job_id: "job-item-1"),
      sequence: 1,
      filename: "split_001.pdf",
      status: "queued"
    )

    assert item.valid?
  end

  test "requires sequence" do
    item = ProcessingItem.new(
      processing_run: ProcessingRun.create!(job_id: "job-item-2"),
      filename: "split_001.pdf"
    )

    assert_not item.valid?
    assert_includes item.errors[:sequence], "can't be blank"
  end

  test "rejects unknown status values" do
    item = ProcessingItem.new(
      processing_run: ProcessingRun.create!(job_id: "job-item-3"),
      sequence: 1,
      filename: "split_001.pdf",
      status: "unknown"
    )

    assert_not item.valid?
    assert_includes item.errors[:status], "is not included in the list"
  end

  test "keeps extracted_document optional" do
    item = ProcessingItem.new(
      processing_run: ProcessingRun.create!(job_id: "job-item-4"),
      sequence: 1,
      filename: "split_001.pdf"
    )

    assert item.valid?
  end
end
