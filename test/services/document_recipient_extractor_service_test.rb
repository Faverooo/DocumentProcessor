require "test_helper"

class DocumentRecipientExtractorServiceTest < ActiveSupport::TestCase
  # Client finto che risponde con il testo fornito — nessuna chiamata HTTP ad AWS.
  def mock_bedrock(response_text)
    content_item = Struct.new(:text).new(response_text)
    message = Struct.new(:content).new([content_item])
    output = Struct.new(:message).new(message)
    response = Struct.new(:output).new(output)
    client = Object.new
    client.define_singleton_method(:converse) { |_args| response }
    client
  end

  # Client che solleva un'eccezione alla chiamata
  def failing_bedrock(error)
    client = Object.new
    client.define_singleton_method(:converse) { |_args| raise error }
    client
  end

  # Client che non deve mai essere chiamato (input vuoto)
  def uncalled_bedrock
    client = Object.new
    client.define_singleton_method(:converse) { |_args| raise "converse non doveva essere chiamato!" }
    client
  end

  # ---------------------------------------------------------------------------
  # Logica di normalizzazione e post-processing
  # ---------------------------------------------------------------------------

  test "rimuove duplicati (testa .uniq)" do
    service = DocumentRecipientExtractorService.new(bedrock_client: mock_bedrock('{"recipients":[{"name":"Mario Rossi"},{"name":"Mario Rossi"}]}'))
    assert_equal ["Mario Rossi"], service.extract("testo documento")[:recipients]
  end

  test "ignora nomi troppo corti — normalize_name scarta < 3 caratteri" do
    service = DocumentRecipientExtractorService.new(bedrock_client: mock_bedrock('{"recipients":[{"name":"A"},{"name":"Mario Rossi"}]}'))
    assert_equal ["Mario Rossi"], service.extract("testo documento")[:recipients]
  end

  test "normalizza spazi multipli — normalize_name pulisce il nome" do
    service = DocumentRecipientExtractorService.new(bedrock_client: mock_bedrock('{"recipients":[{"name":"Mario   Rossi"}]}'))
    assert_equal ["Mario Rossi"], service.extract("testo documento")[:recipients]
  end

  test "estrae anche data, azienda e reparto" do
    response = '{"recipients":[{"name":"Mario Rossi"}],"document":{"date":"2026-03-16","company":"ACME S.p.A.","department":"Risorse Umane"}}'
    service = DocumentRecipientExtractorService.new(bedrock_client: mock_bedrock(response))

    result = service.extract("testo documento")

    assert_equal ["Mario Rossi"], result[:recipients]
    assert_equal "2026-03-16", result[:metadata][:date]
    assert_equal "ACME S.p.A.", result[:metadata][:company]
    assert_equal "Risorse Umane", result[:metadata][:department]
  end

  # ---------------------------------------------------------------------------
  # Edge cases e validazione input
  # ---------------------------------------------------------------------------

  test "ritorna array vuoto se il testo in input e' vuoto — early return, nessuna chiamata a Bedrock" do
    service = DocumentRecipientExtractorService.new(bedrock_client: uncalled_bedrock)
    assert_equal [], service.extract("")[:recipients]
    assert_equal [], service.extract(nil)[:recipients]
    assert_equal [], service.extract("   ")[:recipients]
  end

  # ---------------------------------------------------------------------------
  # Parsing robusto — estrazione JSON dalla risposta LLM
  # ---------------------------------------------------------------------------

  test "estrae JSON anche se LLM aggiunge testo introduttivo — testa regex /\\{.*\\}/m" do
    risposta_con_testo = <<~TXT
      Certamente! Ecco il risultato dell'analisi:
      {"recipients":[{"name":"Mario Rossi"}]}
      Spero di aver risposto correttamente.
    TXT
    service = DocumentRecipientExtractorService.new(bedrock_client: mock_bedrock(risposta_con_testo))
    assert_equal ["Mario Rossi"], service.extract("testo documento")[:recipients]
  end

  # ---------------------------------------------------------------------------
  # Gestione errori — rescue block deve sempre ritornare [] senza eccezioni
  # ---------------------------------------------------------------------------

  test "ritorna array vuoto se il client Bedrock solleva un'eccezione — rescue StandardError" do
    errore = Aws::BedrockRuntime::Errors::ServiceError.new(nil, "timeout")
    service = DocumentRecipientExtractorService.new(bedrock_client: failing_bedrock(errore))
    assert_equal [], service.extract("testo documento")[:recipients]
  end

  test "ritorna array vuoto se la risposta LLM non contiene JSON valido — rescue su regex match nil" do
    service = DocumentRecipientExtractorService.new(bedrock_client: mock_bedrock("risposta senza json"))
    assert_equal [], service.extract("testo documento")[:recipients]
  end

  test "ritorna array vuoto se la risposta LLM e' JSON malformato — rescue su JSON.parse" do
    service = DocumentRecipientExtractorService.new(bedrock_client: mock_bedrock("{recipients: broken"))
    assert_equal [], service.extract("testo documento")[:recipients]
  end
end
