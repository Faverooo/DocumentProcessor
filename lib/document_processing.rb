# Boundary file for the DocumentProcessing module.
#
# This file documents the public surface and intended boundaries of the
# `DocumentProcessing` component. The goal is to make it easier to extract the
# module into a separate gem or engine in the future.
#
# Conventions:
# - Core business classes live under `app/services/document_processing`.
# - Persistence adapters live under `app/services/document_processing/persistence`.
# - Commands (use-cases) live under `app/services/document_processing/commands`.
# - Presenters/Serializers live under `app/services/document_processing/presenters`.
# - Tests for the module live under `test/services/document_processing`.

module DocumentProcessing
  # Add configuration hooks here if needed in the future, for example:
  # mattr_accessor :container_class
  # self.container_class = DocumentProcessing::Container
end
