class ExtractedDocument < ApplicationRecord
  belongs_to :uploaded_document
  belongs_to :matched_employee, class_name: "Employee", optional: true

  enum :status,
    {
      queued: "queued",
      in_progress: "in_progress",
      done: "done",
      failed: "failed",
      sent: "sent",
      validated: "validated"
    },
    validate: true

  validates :sequence, presence: true
  validates :page_start, :page_end, presence: true, numericality: { greater_than: 0 }
  validate :end_page_must_be_after_start

  private

  def end_page_must_be_after_start
    return if page_start.blank? || page_end.blank?
    return if page_end >= page_start

    errors.add(:page_end, "deve essere maggiore o uguale a page_start")
  end
end