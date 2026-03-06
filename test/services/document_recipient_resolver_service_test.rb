require "test_helper"

class DocumentRecipientResolverServiceTest < ActiveSupport::TestCase
  setup do
    @service = DocumentRecipientResolverService.new
  end

  # ---------------------------------------------------------------------------
  # Match esatto
  # ---------------------------------------------------------------------------

  test "ritorna employee con match esatto" do
    result = @service.resolve(recipient_names: ["Mario Rossi"])
    assert_equal employees(:mario_rossi), result
  end

  test "match esatto case-insensitive" do
    result = @service.resolve(recipient_names: ["MARIO ROSSI"])
    assert_equal employees(:mario_rossi), result
  end

  test "match esatto con ordine token invertito" do
    result = @service.resolve(recipient_names: ["Rossi Mario"])
    assert_equal employees(:mario_rossi), result
  end

  # ---------------------------------------------------------------------------
  # Near-exact — nome nel DB con titolo o prefisso extra
  # (la query è subset dei token del nome nel DB → exact_score 0.95)
  # ---------------------------------------------------------------------------

  test "trova mario rossi anche se nel DB c'e' un prefisso extra (token-set containment)" do
    # Simula un DB dove il dipendente si chiama "Dott. Mario Rossi"
    employee = employees(:mario_rossi)
    employee.update!(name: "Dott. Mario Rossi")

    result = @service.resolve(recipient_names: ["Mario Rossi"])
    assert_equal employee, result
  end

  # ---------------------------------------------------------------------------
  # Typo OCR — 1 carattere sbagliato su ogni token
  # ---------------------------------------------------------------------------

  test "typo OCR: maria rossi → Mario Rossi" do
    result = @service.resolve(recipient_names: ["Maria Rossi"])
    assert_equal employees(:mario_rossi), result,
      "Atteso Mario Rossi per typo 'Maria Rossi', got: #{result.inspect}"
  end

  test "typo OCR: mario rosso → Mario Rossi" do
    result = @service.resolve(recipient_names: ["Mario Rosso"])
    assert_equal employees(:mario_rossi), result,
      "Atteso Mario Rossi per typo 'Mario Rosso', got: #{result.inspect}"
  end

  test "typo OCR: maria rosso → Mario Rossi (entrambi i token errati)" do
    result = @service.resolve(recipient_names: ["Maria Rosso"])
    assert_equal employees(:mario_rossi), result,
      "Atteso Mario Rossi per typo 'Maria Rosso', got: #{result.inspect}"
  end

  # ---------------------------------------------------------------------------
  # Nomi con accenti/diacritici
  # ---------------------------------------------------------------------------

  test "trova Klaus Muller anche scritto senza umlaut" do
    result = @service.resolve(recipient_names: ["Klaus Muller"])
    assert_equal employees(:mueller), result
  end

  test "trova Eric Blanc anche senza accento" do
    result = @service.resolve(recipient_names: ["Eric Blanc"])
    assert_equal employees(:eric_blanc), result
  end

  # ---------------------------------------------------------------------------
  # Nessun match → ritorna stringa grezza
  # ---------------------------------------------------------------------------

  test "ritorna stringa grezza se nessun dipendente e' abbastanza simile" do
    result = @service.resolve(recipient_names: ["Zxcvbn Qwerty"])
    assert_equal "Zxcvbn Qwerty", result
  end

  test "nessuna confusione tra rossi e rossini" do
    # "Rossi" da solo non deve matchare "Giovanni Rossini" con score alto
    result = @service.resolve(recipient_names: ["Marco Rossi"])
    # Può matchare Mario Rossi (Rossi in comune) ma NON Rossini
    refute_equal employees(:giovanni_rossini), result
  end

  # ---------------------------------------------------------------------------
  # raw_text come fallback di ricerca
  # ---------------------------------------------------------------------------

  test "usa raw_text se recipient_names e' vuoto" do
    result = @service.resolve(recipient_names: [], raw_text: "Mario Rossi")
    assert_equal employees(:mario_rossi), result
  end

  test "usa raw_text se recipient_names e' nil" do
    result = @service.resolve(recipient_names: nil, raw_text: "Mario Rossi")
    assert_equal employees(:mario_rossi), result
  end

  test "ritorna raw_text grezzo se non trova match dal raw_text" do
    testo = "Spett.le Zxcvbn Qwerty"
    result = @service.resolve(recipient_names: [], raw_text: testo)
    assert_equal testo, result
  end

  test "testo molto lungo (raw_text intero documento) non matcha un dipendente per caso" do
    testo_lungo = "Egregio Dottore, con la presente siamo a comunicarle che " \
                  "il progetto annuale e' stato completato nei tempi previsti. " \
                  "Cordiali saluti, La Direzione Generale dell'Azienda SpA"
    result = @service.resolve(recipient_names: [], raw_text: testo_lungo)
    # Non deve ritornare un Employee — il testo lungo non deve matchare Mario Rossi
    refute_kind_of Employee, result
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  test "ritorna nil se non c'e' nessun testo" do
    assert_nil @service.resolve(recipient_names: [])
    assert_nil @service.resolve(recipient_names: nil)
    assert_nil @service.resolve(recipient_names: [], raw_text: nil)
  end

  test "prende il best match tra piu' recipient_names" do
    # "Luigi Bianchi" è esatto, "Mario Rosso" è un typo
    result = @service.resolve(recipient_names: ["Mario Rosso", "Luigi Bianchi"])
    assert_equal employees(:luigi_bianchi), result
  end

  test "soglia personalizzata piu' bassa accetta match meno precisi" do
    service_permissivo = DocumentRecipientResolverService.new(threshold: 0.50)
    result = service_permissivo.resolve(recipient_names: ["M. Rossi"])
    assert_kind_of Employee, result
  end

  test "soglia personalizzata molto alta rifiuta match parziali" do
    service_severo = DocumentRecipientResolverService.new(threshold: 0.99)
    result = service_severo.resolve(recipient_names: ["Maria Rossi"])
    # Con soglia 0.99 un typo non deve passare
    refute_equal employees(:mario_rossi), result
  end
end
