class ProcessingItem < ApplicationRecord
  belongs_to :processing_run
  belongs_to :extracted_document, optional: true


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
