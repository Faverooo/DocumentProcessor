class UploadedDocument < ApplicationRecord
  has_many :extracted_documents, dependent: :destroy

  enum :file_kind,
    {
      pdf: "pdf",
      csv: "csv",
      image: "image"
    },
    validate: true,
    allow_nil: true

  validates :original_filename, presence: true
  validates :storage_path, presence: true
  validates :page_count, numericality: { greater_than_or_equal_to: 0 }
  validates :checksum, presence: true, uniqueness: true
end