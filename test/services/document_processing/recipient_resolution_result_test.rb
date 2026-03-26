require "test_helper"

class RecipientResolutionResultTest < ActiveSupport::TestCase
  test "raises for invalid status" do
    assert_raises(ArgumentError) do
      DocumentProcessing::RecipientResolutionResult.new(status: :invalid)
    end
  end

  test "matched status predicates" do
    employee = Employee.new(name: "Mario")
    result = DocumentProcessing::RecipientResolutionResult.new(status: :matched, employee: employee)

    assert result.matched?
    assert_not result.unmatched?
    assert_not result.empty?
    assert_equal employee, result.employee
  end

  test "unmatched and empty predicates" do
    unmatched = DocumentProcessing::RecipientResolutionResult.new(status: :unmatched, fallback_text: "Mario")
    empty = DocumentProcessing::RecipientResolutionResult.new(status: :empty)

    assert unmatched.unmatched?
    assert empty.empty?
  end
end
