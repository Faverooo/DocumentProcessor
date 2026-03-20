require "test_helper"

class DocumentProcessingDataExtractorTest < ActiveSupport::TestCase
  def mock_bedrock(response_text)
    content_item = Struct.new(:text).new(response_text)
    message = Struct.new(:content).new([content_item])
    output = Struct.new(:message).new(message)
    response = Struct.new(:output).new(output)
    client = Object.new
    client.define_singleton_method(:converse) { |_args| response }
    client
  end

  def failing_bedrock(error)
    client = Object.new
    client.define_singleton_method(:converse) { |_args| raise error }
    client
  end

  def uncalled_bedrock
    client = Object.new
    client.define_singleton_method(:converse) { |_args| raise "converse non doveva essere chiamato!" }
    client
  end

  test "rimuove duplicati (testa .uniq)" do
    service = DocumentProcessing::DataExtractor.new(bedrock_client: mock_bedrock('{"recipients":[{"name":"Mario Rossi"},{"name":"Mario Rossi"}]}'))
    assert_equal ["Mario Rossi"], service.extract("testo documento")[:recipients]
  end

  test "ignora nomi troppo corti - normalize_name scarta < 3 caratteri" do
    service = DocumentProcessing::DataExtractor.new(bedrock_client: mock_bedrock('{"recipients":[{"name":"A"},{"name":"Mario Rossi"}]}'))
    assert_equal ["Mario Rossi"], service.extract("testo documento")[:recipients]
  end

  test "normalizza spazi multipli - normalize_name pulisce il nome" do
    service = DocumentProcessing::DataExtractor.new(bedrock_client: mock_bedrock('{"recipients":[{"name":"Mario   Rossi"}]}'))
    assert_equal ["Mario Rossi"], service.extract("testo documento")[:recipients]
  end

  test "estrae anche data, azienda e reparto" do
    response = '{"recipients":[{"name":"Mario Rossi"}],"document":{"date":"2026-03-16","company":"ACME S.p.A.","department":"Risorse Umane"}}'
    service = DocumentProcessing::DataExtractor.new(bedrock_client: mock_bedrock(response))

    result = service.extract("testo documento")

    assert_equal ["Mario Rossi"], result[:recipients]
    assert_equal "2026-03-16", result[:metadata][:date]
    assert_equal "ACME S.p.A.", result[:metadata][:company]
    assert_equal "Risorse Umane", result[:metadata][:department]
  end

  test "ritorna struttura vuota se il testo in input e' vuoto" do
    service = DocumentProcessing::DataExtractor.new(bedrock_client: uncalled_bedrock)
    assert_equal [], service.extract("")[:recipients]
    assert_equal [], service.extract(nil)[:recipients]
    assert_equal [], service.extract("   ")[:recipients]
  end

  test "estrae JSON anche se llm aggiunge testo introduttivo" do
    risposta_con_testo = <<~TXT
      Certamente! Ecco il risultato dell'analisi:
      {"recipients":[{"name":"Mario Rossi"}]}
      Spero di aver risposto correttamente.
    TXT

    service = DocumentProcessing::DataExtractor.new(bedrock_client: mock_bedrock(risposta_con_testo))
    assert_equal ["Mario Rossi"], service.extract("testo documento")[:recipients]
  end

  test "ritorna struttura vuota se il client Bedrock solleva un'eccezione" do
    errore = Aws::BedrockRuntime::Errors::ServiceError.new(nil, "timeout")
    service = DocumentProcessing::DataExtractor.new(bedrock_client: failing_bedrock(errore))
    assert_equal [], service.extract("testo documento")[:recipients]
  end

  test "ritorna struttura vuota se la risposta llm non contiene JSON valido" do
    service = DocumentProcessing::DataExtractor.new(bedrock_client: mock_bedrock("risposta senza json"))
    assert_equal [], service.extract("testo documento")[:recipients]
  end

  test "ritorna struttura vuota se la risposta llm e' JSON malformato" do
    service = DocumentProcessing::DataExtractor.new(bedrock_client: mock_bedrock("{recipients: broken"))
    assert_equal [], service.extract("testo documento")[:recipients]
  end
end