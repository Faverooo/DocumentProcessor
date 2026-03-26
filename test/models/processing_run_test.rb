require "test_helper"

class ProcessingRunTest < ActiveSupport::TestCase
  test "is valid with a unique job_id" do
    run = ProcessingRun.new(job_id: "job-1", status: "queued")

    assert run.valid?
  end

  test "requires job_id" do
    run = ProcessingRun.new

    assert_not run.valid?
    assert_includes run.errors[:job_id], "can't be blank"
  end

  test "enforces job_id uniqueness" do
    ProcessingRun.create!(job_id: "job-2")
    duplicate = ProcessingRun.new(job_id: "job-2")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:job_id], "has already been taken"
  end

  test "rejects unknown status values" do
    run = ProcessingRun.new(job_id: "job-3", status: "unknown")

    assert_not run.valid?
    assert_includes run.errors[:status], "is not included in the list"
  end
end
