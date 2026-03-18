class ProcessingRun < ApplicationRecord
  belongs_to :uploaded_document, optional: true
  has_many :processing_items, dependent: :destroy

  enum :status,
    {
      queued: "queued",
      splitting: "splitting",
      processing: "processing",
      completed: "completed",
      failed: "failed"
    },
    validate: true

  validates :job_id, presence: true, uniqueness: true
end
