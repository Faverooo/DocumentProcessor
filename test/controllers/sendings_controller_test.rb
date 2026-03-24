require "test_helper"

class SendingsControllerTest < ActionDispatch::IntegrationTest
  test "create sending and list sendings" do
    recipient = Employee.create!(name: "Gino", email: "gino@x.it", employee_code: "G1")
    ud = UploadedDocument.create!(original_filename: "a.pdf", storage_path: "/tmp/a", page_count: 1, checksum: "ch10")
    ed = ExtractedDocument.create!(uploaded_document: ud, sequence: 1, page_start: 1, page_end: 1)

    post "/sendings", params: { extracted_document_id: ed.id, recipient_id: recipient.id, sent_at: Time.current.iso8601, subject: "Cedolino Marzo" }
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    assert body["sending"]
    assert_equal "Cedolino Marzo", body["sending"]["subject"]

    get "/sendings"
    assert_response :success
    list = JSON.parse(response.body)
    assert list["sendings"].is_a?(Array)
    assert_equal 1, list["sendings"].length
  end

  test "fails to create sending with missing params" do
    post "/sendings", params: { extracted_document_id: nil, recipient_id: 1, sent_at: Time.current.iso8601 }
    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal "error", body["status"]
    assert body["message"].include?("obbligatori")
  end
end
