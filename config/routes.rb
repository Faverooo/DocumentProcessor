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
  post "/documents/test_split", to: "documents#test_split", as: :test_split_documents
  post "/documents/test_data", to: "documents#test_data", as: :test_data_documents
  get "/documents/uploads/:uploaded_document_id/extracted", to: "documents#extracted_index", as: :uploaded_document_extracted_documents
  get "/documents/extracted/:id", to: "documents#extracted_show", as: :extracted_document
  get "/documents/extracted/:id/pdf", to: "documents#extracted_pdf", as: :extracted_pdf_document
  patch "/documents/extracted/:id/reassign_range", to: "documents#reassign_range", as: :reassign_extracted_document_range

  # Defines the root path route ("/")
  root "documents#test"
end
