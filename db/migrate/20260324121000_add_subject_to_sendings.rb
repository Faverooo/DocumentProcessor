class AddSubjectToSendings < ActiveRecord::Migration[8.1]
  def change
    add_column :sendings, :subject, :string
  end
end
