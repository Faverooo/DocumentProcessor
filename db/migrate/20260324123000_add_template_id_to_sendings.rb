class AddTemplateIdToSendings < ActiveRecord::Migration[8.1]
  def change
    add_column :sendings, :template_id, :integer
    add_index :sendings, :template_id
    add_foreign_key :sendings, :templates, column: :template_id
  end
end
