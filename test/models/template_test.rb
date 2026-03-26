require "test_helper"

class TemplateTest < ActiveSupport::TestCase
  test "is valid with subject and optional body" do
    template = Template.new(subject: "Oggetto", body: "Contenuto")

    assert template.valid?
  end

  test "requires subject" do
    template = Template.new(body: "Contenuto")

    assert_not template.valid?
    assert_includes template.errors[:subject], "can't be blank"
  end

  test "validates subject maximum length" do
    template = Template.new(subject: "a" * 256)

    assert_not template.valid?
    assert_includes template.errors[:subject], "is too long (maximum is 255 characters)"
  end

  test "validates body maximum length" do
    template = Template.new(subject: "Oggetto", body: "a" * 65_536)

    assert_not template.valid?
    assert_includes template.errors[:body], "is too long (maximum is 65535 characters)"
  end
end
