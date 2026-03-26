require "test_helper"

class ExtractedMetadataBuilderTest < ActiveSupport::TestCase
  test "build uses metadata when no overrides" do
    metadata = { company: "ACME", department: "HR", type: "payroll", date: "2026-03", reason: "monthly", competence: "2026-03" }

    result = DocumentProcessing::ExtractedMetadataBuilder.new(metadata: metadata).build

    assert_equal "ACME", result[:company]
    assert_equal "HR", result[:department]
    assert_equal "payroll", result[:type]
    assert_equal "2026-03", result[:date]
    assert_equal "monthly", result[:reason]
    assert_equal "2026-03", result[:competence]
  end

  test "build applies uploaded document overrides" do
    uploaded = UploadedDocument.new(
      override_company: "Override Co",
      override_department: "Override Dept",
      category: "custom_type",
      competence_period: "2026-04"
    )

    result = DocumentProcessing::ExtractedMetadataBuilder.new(
      metadata: { company: "ACME", department: "HR", type: "payroll", date: "2026-03", competence: "2026-03" },
      uploaded_document: uploaded
    ).build

    assert_equal "Override Co", result[:company]
    assert_equal "Override Dept", result[:department]
    assert_equal "custom_type", result[:type]
    assert_equal "2026-04", result[:date]
    assert_equal "2026-04", result[:competence]
  end
end
