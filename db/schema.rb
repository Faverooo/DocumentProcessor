# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_04_084442) do
  create_table "employees", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "employee_code"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "processed_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "employee_id", null: false
    t.string "filename"
    t.string "recipient_name"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_processed_documents_on_employee_id"
  end

  add_foreign_key "processed_documents", "employees"
end
