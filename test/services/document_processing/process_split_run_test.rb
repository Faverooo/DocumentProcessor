require "test_helper"

class ProcessSplitRunTest < ActiveSupport::TestCase
  class FakeSplitRunRepository
    attr_reader :failed_error_message, :post_split_count

    def initialize(run:, created_artifacts: [])
      @run = run
      @created_artifacts = created_artifacts
      @failed_error_message = nil
      @post_split_count = nil
    end

    def find_run_by_job_id!(_job_id)
      @run
    end

    def mark_splitting!(_run)
    end

    def create_split_artifacts!(run:, split_results:)
      @post_split_count = split_results.size
      @created_artifacts
    end

    def mark_post_split_state!(run:, split_count:)
      @post_split_count = split_count
    end

    def mark_failed(run:, error_message:)
      @failed_error_message = error_message
    end

    def uploaded_source_path_for(_run)
      nil
    end
  end

  class FakeNotifier
    attr_reader :events

    def initialize
      @events = []
    end

    def broadcast(job_id, payload)
      @events << [job_id, payload]
    end
  end

  class FakeFileStorage
    def exist?(_path)
      false
    end

    def delete(_path)
    end

    def expanded(path)
      path
    end
  end

  class FakeContainer
    attr_reader :split_run_repository, :notifier

    def initialize(split_run_repository:, notifier:, split_results:, file_storage: FakeFileStorage.new)
      @split_run_repository = split_run_repository
      @notifier = notifier
      @split_results = split_results
      @file_storage = file_storage
    end

    def pdf_splitter(pdf:)
      splitter = Object.new
      split_results = @split_results
      splitter.define_singleton_method(:split) { split_results }
      splitter
    end

    def file_storage
      @file_storage
    end
  end

  test "enqueues extraction jobs and broadcasts split completion" do
    run = Struct.new(:job_id).new("job-1")
    artifacts = [{ path: "/tmp/mini_1.pdf", processing_item_id: 10, extracted_document_id: 20 }]
    repository = FakeSplitRunRepository.new(run: run, created_artifacts: artifacts)
    notifier = FakeNotifier.new
    container = FakeContainer.new(
      split_run_repository: repository,
      notifier: notifier,
      split_results: [{ path: "/tmp/mini_1.pdf", range: { start: 0, end: 1 } }]
    )

    pdf = Struct.new(:pages).new([1, 2])
    job_calls = []

    original_pdf_load = CombinePDF.method(:load)
    original_job_perform = DataExtractionJob.method(:perform_later)

    CombinePDF.define_singleton_method(:load) { |_path| pdf }
    DataExtractionJob.define_singleton_method(:perform_later) { |*args| job_calls << args }

    begin
      DocumentProcessing::ProcessSplitRun.new(container: container).call(file_path: "/tmp/source.pdf", job_id: "job-1")
    ensure
      CombinePDF.define_singleton_method(:load, original_pdf_load)
      DataExtractionJob.define_singleton_method(:perform_later, original_job_perform)
    end

    assert_equal 1, job_calls.size
    assert_equal "/tmp/mini_1.pdf", job_calls.first[0]
    assert_equal 1, notifier.events.size
    assert_equal "split_completed", notifier.events.first[1][:event]
    assert_equal "success", notifier.events.first[1][:status]
    assert_equal 1, repository.post_split_count
  end

  test "broadcasts processing_completed when split returns no files" do
    run = Struct.new(:job_id).new("job-empty")
    repository = FakeSplitRunRepository.new(run: run, created_artifacts: [])
    notifier = FakeNotifier.new
    container = FakeContainer.new(split_run_repository: repository, notifier: notifier, split_results: [])

    pdf = Struct.new(:pages).new([])

    original_pdf_load = CombinePDF.method(:load)
    CombinePDF.define_singleton_method(:load) { |_path| pdf }

    begin
      DocumentProcessing::ProcessSplitRun.new(container: container).call(file_path: "/tmp/source.pdf", job_id: "job-empty")
    ensure
      CombinePDF.define_singleton_method(:load, original_pdf_load)
    end

    assert_equal 2, notifier.events.size
    assert_equal "split_completed", notifier.events[0][1][:event]
    assert_equal "processing_completed", notifier.events[1][1][:event]
    assert_equal 0, repository.post_split_count
  end

  test "marks run as failed and broadcasts error on exception" do
    run = Struct.new(:job_id).new("job-error")
    repository = FakeSplitRunRepository.new(run: run, created_artifacts: [])
    notifier = FakeNotifier.new
    container = FakeContainer.new(split_run_repository: repository, notifier: notifier, split_results: [])

    original_pdf_load = CombinePDF.method(:load)
    CombinePDF.define_singleton_method(:load) { |_path| raise "boom" }

    begin
      DocumentProcessing::ProcessSplitRun.new(container: container).call(file_path: "/tmp/source.pdf", job_id: "job-error")
    ensure
      CombinePDF.define_singleton_method(:load, original_pdf_load)
    end

    assert_equal "boom", repository.failed_error_message
    assert_equal 1, notifier.events.size
    assert_equal "error", notifier.events.first[1][:status]
  end
end
