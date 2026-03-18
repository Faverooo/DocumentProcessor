class UploadedDocument < ApplicationRecord
  has_many :extracted_documents, dependent: :destroy

  validates :original_filename, presence: true
  validates :storage_path, presence: true
  validates :page_count, numericality: { greater_than_or_equal_to: 0 }
end