namespace :pdf do
  desc "Test estrazione dati documento e matching destinatario da PDF singolo (senza split)"
  task :test_data, [:file_path] => :environment do |_t, args|
    require "aws-sdk-textract"
    require "aws-sdk-bedrockruntime"
    require "combine_pdf"

    file_path = args[:file_path]
    unless file_path && File.exist?(file_path)
      puts "File non trovato: #{file_path}"
      puts "Uso: bin/rails pdf:test_data['path/to/document.pdf']"
      exit 1
    end

    puts "=" * 70
    puts "TEST ESTRAZIONE DATI DOCUMENTO E MATCHING"
    puts "=" * 70
    puts "File: #{file_path}"
    puts

    pdf = CombinePDF.load(file_path)
    puts "PDF caricato: #{pdf.pages.size} pagina/e"
    puts

    puts "Estrazione testo con OCR..."
    textract = Aws::Textract::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
    ocr_service = DocumentOcrService.new(textract_client: textract)
    ocr_result = ocr_service.full_ocr(file_path)
    full_text = ocr_result[:text]

    puts "OCR completato: #{full_text.length} caratteri"
    puts
    puts "-" * 70
    puts "TESTO ESTRATTO:"
    puts "-" * 70
    puts full_text
    puts
    puts

    puts "Estrazione dati con LLM..."
    bedrock = Aws::BedrockRuntime::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"))
    extractor = DocumentDataExtractorService.new(bedrock_client: bedrock)
    extracted_data = extractor.extract(full_text)
    recipient_names = extracted_data[:recipients]

    if recipient_names.empty? && extracted_data[:metadata].values.compact.empty?
      puts "Nessun dato estratto dal LLM"
      puts
      exit 0
    end

    puts "Destinatari estratti: #{recipient_names.inspect}"
    puts "Metadati estratti: #{extracted_data[:metadata].inspect}"
    puts
    puts

    puts "Matching con database dipendenti..."
    resolver = DocumentRecipientResolverService.new

    recipient_names.each_with_index do |recipient_name, idx|
      puts "-" * 70
      puts "Destinatario ##{idx + 1}: \"#{recipient_name}\""
      puts "-" * 70

      result = resolver.resolve(recipient_names: [recipient_name])

      if result.matched?
        puts "MATCH TROVATO"
        puts "   ID:       #{result.employee.id}"
        puts "   Nome:     #{result.employee.name}"
        puts "   Email:    #{result.employee.email}"
      else
        puts "NESSUN MATCH (score < soglia)"
        puts "   Testo grezzo salvato: \"#{result.fallback_text}\""
      end

      puts
    end

    puts "=" * 70
    puts "Test completato"
    puts "=" * 70
  end
end