class Sending < ApplicationRecord
  belongs_to :extracted_document
  belongs_to :recipient, class_name: "Employee"
  belongs_to :template, optional: true

  validates :extracted_document, presence: true
  validates :recipient, presence: true
  validates :sent_at, presence: true
  validates :subject, length: { maximum: 255 }, allow_blank: true
  validates :body, length: { maximum: 10_000 }, allow_blank: true
end
