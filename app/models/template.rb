class Template < ApplicationRecord
  validates :subject, presence: true, length: { maximum: 255 }
  validates :body, length: { maximum: 65_535 }, allow_blank: true
end
