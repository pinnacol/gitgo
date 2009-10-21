require 'gitgo/utils/sorted_to_yaml'

module Gitgo
  class Document
    class << self

      protected

      def attribute_reader(key)
        key = key.to_s
        define_method(key) do
          attributes[key]
        end
      end

      def attribute_writer(key)
        key = key.to_s
        define_method("#{key}=") do |input|
          attributes[key] = input
        end
      end

      def attribute(*keys)
        keys.each do |key|
          attribute_reader(key)
          attribute_writer(key)
        end
      end
    end
    
    attribute :author
    
    attribute :date
    
    attribute :content
    
    def initialize(attributes={}, sha=nil)
      case attributes
      when Hash
        @attributes = attributes
        @str = nil
      when String
        @attributes = nil
        @str = attributes
      else
        raise "invalid content: #{content}"
      end
      
      @sha = sha
    end
    
    def attributes
      @attributes ||= begin
        attrs, content = @str.split(/\n--- \n/m, 2)
        attrs = YAML.load(attrs) || {}
        attrs['content'] = content
        attrs
      end
    end
    
    def sha
      @sha ||= begin
        Digest::SHA1.hexdigest(self.to_s)[0, 40]
      end
    end
    
    def to_s
      @str ||= begin
        attrs = @attributes.dup
        attrs.extend(Utils::SortedToYaml)
        content = attrs.delete('content')
        "#{attrs.to_yaml}--- \n#{content}"
      end
    end
  end
end