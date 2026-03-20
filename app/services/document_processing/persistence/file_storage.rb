module DocumentProcessing
  module Persistence
    class FileStorage
      def exist?(path)
        File.exist?(path)
      end

      def delete(path)
        File.delete(path)
      end

      def expanded(path)
        File.expand_path(path)
      end
    end
  end
end
