class RemoveMatchedEmployeeFromProcessingItems < ActiveRecord::Migration[7.0]
  def change
    # Remove foreign key if present, then remove index and reference column
    if foreign_key_exists?(:processing_items, column: :matched_employee_id)
      remove_foreign_key :processing_items, column: :matched_employee_id
    end

    if index_exists?(:processing_items, :matched_employee_id)
      remove_index :processing_items, :matched_employee_id
    end

    if column_exists?(:processing_items, :matched_employee_id)
      remove_reference :processing_items, :matched_employee, index: false, foreign_key: false
    end
  end
end
