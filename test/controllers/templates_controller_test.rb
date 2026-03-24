require "test_helper"

class TemplatesControllerTest < ActionDispatch::IntegrationTest
  test "create and list templates and show" do
    post "/templates", params: { subject: "Oggetto A", body: "Testo A" }
    assert_response :created
    created = JSON.parse(response.body)["template"]
    assert_equal "Oggetto A", created["subject"]

    get "/templates"
    assert_response :success
    list = JSON.parse(response.body)["templates"]
    assert list.any? { |t| t["id"] == created["id"] }

    get "/templates/#{created["id"]}"
    assert_response :success
    show = JSON.parse(response.body)["template"]
    assert_equal "Testo A", show["body"]
  end
end
