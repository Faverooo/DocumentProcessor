class CreateTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :templates do |t|
      t.string :subject, null: false
      t.text :body

      t.timestamps
    end
  end
end
