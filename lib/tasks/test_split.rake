namespace :pdf do
  desc "Testa lo split di un PDF multi-documento"
  task :split, [:file_path] => :environment do |_task, args|
    unless args[:file_path]
      puts "❌ Errore: specifica il path del PDF"
      puts "Uso: bin/rails pdf:split['/path/to/documento.pdf']"
      exit 1
    end

    pdf_path = args[:file_path]
    unless File.exist?(pdf_path)
      puts "❌ File non trovato: #{pdf_path}"
      exit 1
    end

    puts "📄 Testando split di: #{File.basename(pdf_path)}"
    puts "=" * 80

    # 1. Carica il PDF
    puts "\n📖 STEP 1: Caricamento PDF..."
    pdf = CombinePDF.load(pdf_path)
    puts "   ✓ Caricate #{pdf.pages.size} pagine totali"

    # 2. Crea i servizi necessari
    puts "\n⚙️  STEP 2: Inizializzazione servizi..."
    ocr_service = DocumentOcrService.new
    splitter = DocumentPdfSplitterService.new(pdf: pdf, ocr_service: ocr_service)
    puts "   ✓ OCR service e splitter pronti"

    # 3. Esegui lo split
    puts "\n🔪 STEP 3: Analisi e split del documento..."
    puts "   (Questo può richiedere tempo: OCR + chiamata LLM)\n"
    
    begin
      # Mostra dettagli del processo
      puts "   📝 Estraendo testo dalle pagine con OCR..."
      page_texts = ocr_service.page_texts_with_layout(pdf)
      puts "      ✓ Estratto testo da #{page_texts.size} pagine"
      
      # Mostra anteprima delle prime righe di ogni pagina
      puts "\n   📋 Anteprima prime righe per pagina:"
      page_texts.first(3).each_with_index do |text, idx|
        preview = text.lines.first(3).join(" ").strip[0..80]
        puts "      Pag #{idx + 1}: #{preview}..."
      end
      puts "      ..." if page_texts.size > 3
      
      mini_pdfs = splitter.split
      
      puts "\n" + "=" * 80
      puts "📊 RISULTATO:"
      puts "=" * 80
      puts "✅ Split completato!"
      puts "   Documenti trovati: #{mini_pdfs.size}"
      
      mini_pdfs.each_with_index do |path, idx|
        file_size = File.size(path) / 1024.0
        puts "   #{idx + 1}. #{File.basename(path)} (#{file_size.round(1)} KB)"
      end
      
      puts "\n💡 I file temporanei sono salvati in:"
      puts "   #{File.dirname(mini_pdfs.first)}"
      
    rescue StandardError => e
      puts "\n❌ ERRORE durante lo split:"
      puts "   #{e.class}: #{e.message}"
      puts "\n🔍 Stack trace:"
      puts e.backtrace.first(5).map { |line| "   #{line}" }.join("\n")
    end

    puts "\n✨ Test completato!"
  end

  # Backwards compatible alias
  task :test_split => :split
end
