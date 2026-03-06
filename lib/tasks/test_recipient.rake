namespace :pdf do
  desc "Test estrazione destinatario e matching da PDF singolo (senza split)"
  task :test_recipient, [:file_path] => :environment do |_t, args|
    require "aws-sdk-textract"
    require "aws-sdk-bedrockruntime"
    require "combine_pdf"

    file_path = args[:file_path]
    unless file_path && File.exist?(file_path)
      puts "❌ File non trovato: #{file_path}"
      puts "Uso: bin/rails pdf:test_recipient['path/to/document.pdf']"
      exit 1
    end

    puts "═" * 70
    puts "📄 TEST ESTRAZIONE DESTINATARIO E MATCHING"
    puts "═" * 70
    puts "File: #{file_path}"
    puts

    # ─── 1. CARICA PDF ────────────────────────────────────────────────
    pdf = CombinePDF.load(file_path)
    puts "✓ PDF caricato: #{pdf.pages.size} pagina/e"
    puts

    # ─── 2. OCR con AWS Textract ──────────────────────────────────────
    puts "🔍 Estrazione testo con OCR..."
    textract = Aws::Textract::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
    ocr_service = DocumentOcrService.new(textract_client: textract)
    
    full_text = ocr_service.full_ocr(file_path)
    
    puts "✓ OCR completato: #{full_text.length} caratteri"
    puts
    puts "─" * 70
    puts "TESTO ESTRATTO:"
    puts "─" * 70
    puts full_text
    puts
    puts

    # ─── 3. ESTRAZIONE DESTINATARI con LLM ───────────────────────────
    puts "🤖 Estrazione destinatari con LLM..."
    bedrock = Aws::BedrockRuntime::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
    extractor = DocumentRecipientExtractorService.new(bedrock_client: bedrock)
    
    recipients = extractor.extract(full_text)
    
    if recipients.empty?
      puts "⚠️  Nessun destinatario estratto dal LLM"
      puts
      exit 0
    end
    
    puts "✓ Destinatari estratti: #{recipients.inspect}"
    puts
    puts

    # ─── 4. MATCHING CON DATABASE (fuzzy logic) ──────────────────────
    puts "🎯 Matching con database dipendenti..."
    resolver = DocumentRecipientResolverService.new
    
    recipients.each_with_index do |recipient_name, idx|
      puts "─" * 70
      puts "Destinatario ##{idx + 1}: \"#{recipient_name}\""
      puts "─" * 70
      
      result = resolver.resolve(recipient_names: [recipient_name])
      
      if result.is_a?(Employee)
        puts "✅ MATCH TROVATO"
        puts "   ID:       #{result.id}"
        puts "   Nome:     #{result.name}"
        puts "   Email:    #{result.email}"
      else
        puts "❌ NESSUN MATCH (score < soglia)"
        puts "   Testo grezzo salvato: \"#{result}\""
      end
      
      puts
    end

    puts "═" * 70
    puts "✓ Test completato"
    puts "═" * 70
  end
end
