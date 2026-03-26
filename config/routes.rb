Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Test servizi
  get "/documents/test", to: "documents#test", as: :test_documents
  post "/documents/split", to: "documents#split", as: :split_documents
  post "/documents/test_data", to: "documents#test_data", as: :test_data_documents
  post "/documents/process_file", to: "documents#process_file", as: :process_file_documents
  get "/documents/uploads/:uploaded_document_id/extracted", to: "documents#extracted_index", as: :uploaded_document_extracted_documents
  get "/documents/uploads", to: "documents#uploads", as: :uploaded_documents
  get "/documents/uploads/:id/file", to: "documents#uploaded_file", as: :uploaded_document_file
  get "/documents/extracted/:id", to: "documents#extracted_show", as: :extracted_document
  get "/documents/extracted/:id/pdf", to: "documents#extracted_pdf", as: :extracted_pdf_document
  patch "/documents/extracted/:id/reassign_range", to: "documents#reassign_range", as: :reassign_extracted_document_range
  patch "/documents/extracted/:id/metadata", to: "documents#update_metadata", as: :update_extracted_document_metadata
  patch "/documents/extracted/:id/validate", to: "documents#validate_extracted", as: :validate_extracted_document

  # Lookups: aziende e utenti
  get "/lookups/companies", to: "lookups#companies", as: :lookups_companies
  get "/lookups/users", to: "lookups#users", as: :lookups_users

  # Sendings (invii)
  get "/sendings", to: "sendings#index", as: :sendings
  post "/sendings", to: "sendings#create", as: :create_sending

  # Templates (modelli di invio)
  get "/templates", to: "templates#index", as: :templates
  get "/templates/:id", to: "templates#show", as: :template
  post "/templates", to: "templates#create", as: :create_template

  # Defines the root path route ("/")
  root "documents#test"
end
