require 'gitgo/git'

module Gitgo
  class Document
    module Utils
      AUTHOR = /\A.*?<.*?>\z/
      DATE = /\A\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d-\d\d:\d\d\z/
      SHA = Git::SHA
      
      def blank?(obj)
        obj.nil? || obj.to_s.strip.empty?
      end
      
      def validate_not_blank(str)
        if blank?(str)
          raise 'nothing specified'
        end
      end
      
      def validate_format(value, format)
        if value.nil?
          raise 'missing'
        end
        
        unless value =~ format
          raise 'misformatted'
        end
      end
      
      def validate_format_or_nil(value, format)
        value.nil? || validate_format(value, format)
      end
      
      def validate_array_or_nil(value)
        unless value.nil? || value.kind_of?(Array)
          raise 'not an array'
        end
      end
      
      def arrayify(obj)
        case obj
        when Array then obj
        when nil   then []
        else [obj]
        end
      end
    end
  end
end