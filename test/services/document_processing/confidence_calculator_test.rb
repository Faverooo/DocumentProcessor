require "test_helper"

class ConfidenceCalculatorTest < ActiveSupport::TestCase
  test "global_confidence merges llm and textract confidences" do
    calculator = DocumentProcessing::ConfidenceCalculator.new(
      ocr_lines: [
        { text: "Mario Rossi", confidence: 80 },
        { text: "ACME SPA", confidence: 90 },
        { text: "15/03/2026", confidence: 70 }
      ],
      recipient_names: ["Mario Rossi"],
      metadata: { date: "2026-03-15", company: "ACME SPA", department: nil, reason: nil, competence: nil },
      llm_confidence: { recipient: 0.6, date: 0.5, company: 0.4, department: 0.2, type: 0.9, reason: 0.0, competence: 0.0 }
    )

    result = calculator.global_confidence

    assert_equal 0.7, result[:recipient]
    assert_equal 0.6, result[:date]
    assert_equal 0.65, result[:company]
    assert_equal 0.9, result[:type]
  end

  test "overrides force confidence to 1.0" do
    uploaded = UploadedDocument.new(
      override_company: "X",
      override_department: "Y",
      category: "Z",
      competence_period: "2026-01"
    )

    calculator = DocumentProcessing::ConfidenceCalculator.new(
      ocr_lines: [],
      recipient_names: [],
      metadata: {},
      llm_confidence: {},
      uploaded_document: uploaded
    )

    result = calculator.global_confidence

    assert_equal 1.0, result[:company]
    assert_equal 1.0, result[:department]
    assert_equal 1.0, result[:type]
    assert_equal 1.0, result[:competence]
  end
end
