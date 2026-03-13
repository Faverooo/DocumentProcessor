class ProcessingItem < ApplicationRecord
  belongs_to :processing_run
  belongs_to :matched_employee, class_name: "Employee", optional: true

  enum :status,
    {
      queued: "queued",
      in_progress: "in_progress",
      done: "done",
      failed: "failed"
    },
    validate: true

  validates :sequence, presence: true
end
