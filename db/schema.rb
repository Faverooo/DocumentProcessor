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

ActiveRecord::Schema[8.1].define(version: 2026_03_26_093000) do
  create_table "employees", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "employee_code"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "extracted_documents", force: :cascade do |t|
    t.json "confidence", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "matched_employee_id"
    t.json "metadata", default: {}, null: false
    t.integer "page_end", null: false
    t.integer "page_start", null: false
    t.float "process_time_seconds"
    t.datetime "processed_at"
    t.string "recipient"
    t.integer "sequence", null: false
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.integer "uploaded_document_id", null: false
    t.index ["matched_employee_id"], name: "index_extracted_documents_on_matched_employee_id"
    t.index ["status"], name: "index_extracted_documents_on_status"
    t.index ["uploaded_document_id", "sequence"], name: "index_extracted_documents_on_uploaded_document_id_and_sequence", unique: true
    t.index ["uploaded_document_id"], name: "index_extracted_documents_on_uploaded_document_id"
  end

  create_table "processing_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "extracted_document_id"
    t.string "filename", null: false
    t.integer "processing_run_id", null: false
    t.integer "sequence", null: false
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["extracted_document_id"], name: "index_processing_items_on_extracted_document_id"
    t.index ["processing_run_id", "sequence"], name: "index_processing_items_on_processing_run_id_and_sequence", unique: true
    t.index ["processing_run_id"], name: "index_processing_items_on_processing_run_id"
    t.index ["status"], name: "index_processing_items_on_status"
  end

  create_table "processing_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "job_id", null: false
    t.string "original_filename"
    t.integer "processed_documents", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.integer "total_documents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "uploaded_document_id"
    t.index ["job_id"], name: "index_processing_runs_on_job_id", unique: true
    t.index ["status"], name: "index_processing_runs_on_status"
    t.index ["uploaded_document_id"], name: "index_processing_runs_on_uploaded_document_id"
  end

  create_table "sendings", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "extracted_document_id", null: false
    t.integer "recipient_id", null: false
    t.datetime "sent_at", null: false
    t.string "subject"
    t.integer "template_id"
    t.datetime "updated_at", null: false
    t.index ["extracted_document_id"], name: "index_sendings_on_extracted_document_id"
    t.index ["recipient_id"], name: "index_sendings_on_recipient_id"
    t.index ["template_id"], name: "index_sendings_on_template_id"
  end

  create_table "templates", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
  end

  create_table "uploaded_documents", force: :cascade do |t|
    t.string "category"
    t.string "checksum"
    t.string "competence_period"
    t.datetime "created_at", null: false
    t.string "file_kind"
    t.string "original_filename", null: false
    t.string "override_company"
    t.string "override_department"
    t.integer "page_count", default: 0, null: false
    t.string "storage_path", null: false
    t.datetime "updated_at", null: false
    t.index ["checksum"], name: "index_uploaded_documents_on_checksum", unique: true
    t.index ["file_kind"], name: "index_uploaded_documents_on_file_kind"
  end

  add_foreign_key "extracted_documents", "employees", column: "matched_employee_id"
  add_foreign_key "extracted_documents", "uploaded_documents"
  add_foreign_key "processing_items", "extracted_documents"
  add_foreign_key "processing_items", "processing_runs"
  add_foreign_key "processing_runs", "uploaded_documents"
  add_foreign_key "sendings", "employees", column: "recipient_id"
  add_foreign_key "sendings", "extracted_documents"
  add_foreign_key "sendings", "templates"
end
