module Gitgo
  class Document
    # Raised by Document#validate for an invalid document.
    class InvalidDocumentError < StandardError
      attr_reader :doc
      attr_reader :errors
      
      def initialize(doc, errors)
        @doc = doc
        @errors = errors
        super format_errors
      end
      
      def format_errors
        lines = []
        errors.keys.sort.each do |key|
          error = errors[key]
          lines << "#{key}: #{error.message} (#{error.class})"
        end
        
        lines.unshift header(lines.length)
        lines.join("\n")
      end
      
      def header(n)
        case n
        when 0 then "unknown errors"
        when 1 then "found 1 error:"
        else "found #{n} errors:"
        end
      end
    end
  end
end