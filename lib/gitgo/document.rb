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
    
    attribute :type
    
    attribute :content
    
    attr_accessor :sha
    
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
    
    def each_pair
      attributes.keys.sort!.each do |key|
        next unless value = attributes[key]
        yield(key, value)
      end
    end
    
    def [](key)
      attributes[key]
    end
    
    def attributes
      @attributes ||= begin
        attrs, content = @str.split(/\n--- \n/m, 2)
        attrs = YAML.load(attrs) if attrs
        attrs ||= {}
        if author = attrs['author']
          attrs['author'] = Grit::Actor.from_string(author)
        end
        attrs['content'] = content
        attrs
      end
    end
    
    def merge(attrs)
      Document.new(attributes.merge(attrs))
    end
    
    def to_s
      @str ||= begin
        attrs = @attributes.dup
        attrs['author'] = "#{author.name} <#{author.email}>"
        content = attrs.delete('content')
        
        attrs.extend(SortedToYaml)
        "#{attrs.to_yaml}--- \n#{content}"
      end
    end
    
    # From: http://snippets.dzone.com/posts/show/5811
    module SortedToYaml
      
      # Replacing the to_yaml function so it'll serialize hashes sorted (by their keys)
      #
      # Original function is in /usr/lib/ruby/1.8/yaml/rubytypes.rb
      def to_yaml( opts = {} )
        YAML::quick_emit( object_id, opts ) do |out|
          out.map( taguri, to_yaml_style ) do |map|
            sort.each do |k, v|   # <-- here's my addition (the 'sort')
              map.add( k, v )
            end
          end
        end
      end
    end
  end
end