require "test_helper"

class EmployeeTest < ActiveSupport::TestCase
  test "is valid without optional attributes" do
    employee = Employee.new

    assert employee.valid?
  end

  test "persists with full attributes" do
    employee = Employee.new(name: "Mario Rossi", email: "mario.rossi@azienda.it", employee_code: "EMP001")

    assert employee.valid?
    assert employee.save
  end
end
