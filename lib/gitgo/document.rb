require 'grit/actor'

module Gitgo
  
  # Document represents the standard format in which Gitgo serializes
  # comments, issues, and pages.
  #
  # == Format
  #
  # Documents consist of an attributes section and a content section, joined
  # as a YAML document plus a string:
  #
  #   [example]
  #   --- 
  #   author: John Doe <john.doe@email.com>
  #   date: 1252508400.123
  #   --- 
  #   content...
  #
  # The author and date fields are mandatory, and must be formatted as shown
  # where the author records both the author name and email and the date is in
  # a numeric format.  The content is read literally as everything following
  # the break.
  #
  class Document
    class << self
      
      # Parses a Document from the string.
      def parse(str, sha=nil)
        attrs, content = str.split(/\n--- \n/m, 2)
        attrs = attrs.nil? || attrs.empty? ? nil : YAML.load(attrs)
        attrs ||= {}
        
        unless attrs.kind_of?(Hash)
          raise "no attributes specified"
        end

        new(attrs, content, sha)
      rescue
        raise if $DEBUG
        raise "invalid document: (#{$!.message})\n#{str}"
      end
    end
    
    RESERVED_KEYS = %w{author date}
    
    attr_reader :author
    attr_reader :date
    attr_reader :content
    attr_accessor :sha
    
    # Initializes a new Document.  Author and date can be specified as strings
    # in their serialized formats:
    #
    #   doc = Document.new(
    #     "author" => "John Doe <john.doe@email.com>",
    #     "date" => "1252508400.123")
    #
    #   doc.author.name       # => "John Doe"
    #   doc.date.to_f         # => 1252508400.123
    #
    # Or as as Grit::Actor and Time objects:
    #
    #   author = Grit::Actor.new("John Doe", "john.doe@email.com")
    #   date = Time.now
    #
    #   doc = Document.new("author" => author, "date" => date)
    #   doc.author.name       # => "John Doe"
    #   doc.date              # => date
    #
    def initialize(attrs={}, content=nil, sha=nil)
      self.author = attrs.delete('author')
      self.date = attrs.delete('date')
      @attrs = attrs
      @content = content
      @sha = sha
    end
    
    # Sets the author.  Author can be specified as a Grit::Actor or as a
    # string in the standard author format.  Raises an error if set to nil.
    def author=(author)
      @author = case author
      when String
        Grit::Actor.from_string(author)
      when nil
        raise "author cannot be nil"
      else
        author
      end
    end
    
    # Sets the date.  Date can be specified as a Time, a numeric, or a string
    # in the standard date format (see new for more details). Raises an error
    # if set to nil.
    def date=(date)
      @date = case date
      when Numeric
        Time.at(date)
      when String
        sec, usec = date.split(".")
        Time.at(sec.to_i, usec.to_i)
      when nil
        raise "date cannot be nil"
      else
        date
      end
    end
    
    # Gets an attribute.
    def [](key)
      if RESERVED_KEYS.include?(key)
        send(key)
      else
        @attrs[key]
      end
    end
    
    # Sets an attribute.
    def []=(key, value)
      if RESERVED_KEYS.include?(key)
        send("#{key}=", value)
      else
        @attrs[key] = value
      end
    end
    
    # Returns the attributes for self.  Attributes cannot be set through this
    # method; use ASET instead.
    def attributes(all=true)
      all ? @attrs.merge('author' => author, 'date' => date) : @attrs.dup
    end
    
    # Yields each attribute to the block, sorted by key.
    def each_pair
      attributes = self.attributes
      attributes.keys.sort!.each do |key|
        yield(key, attributes[key])
      end
    end
    
    # Merges the attributes and content with self to produce a new Document.
    # If content is nil, then the content for self will be used.
    def merge(attrs, content=nil)
      Document.new(attributes.merge(attrs), content || self.content)
    end
    
    # Serializes self into a string according to the document format.
    def to_s
      attributes = @attrs.merge(
        "author" => "#{author.name} <#{author.email}>",
        "date" => date.to_f
      ).extend(SortedToYaml)
      
      "#{attributes.to_yaml}--- \n#{content}"
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