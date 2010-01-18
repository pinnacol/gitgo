require 'grit/actor'
require 'shellwords'

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
  # The author and date fields are mandatory, and must be formatted as shown.
  # Specifically the author must consist of a user name and email in the git
  # format and the date must be a number. The content consists of everything
  # following the break.
  #
  class Document
    class << self
      
      # Parses a Document from the string.
      def parse(str, sha=nil)
        attrs, content = str.split(/\n--- \n/m, 2)
        
        if attrs.nil? || attrs.empty?
          raise InvalidDocumentError, "no attributes specified:\n#{str}"
        end
        
        attrs = YAML.load(attrs)
        unless attrs.kind_of?(Hash)
          raise InvalidDocumentError, "no attributes specified:\n#{str}"
        end
        
        if content.nil?
          raise InvalidDocumentError, "no content specified:\n#{str}"
        end
        
        new(attrs, content, sha)
      rescue
        raise if $DEBUG || $!.kind_of?(InvalidDocumentError)
        raise InvalidDocumentError, "invalid document: (#{$!.message})\n#{str}"
      end
    end
    
    # The author key
    AUTHOR = 'author'
    
    # The date key
    DATE = 'date'
    
    # The tags key
    TAGS = 'tags'
    
    # An array of keys that will be indexed if present (author is automatic)
    INDEX_KEYS = %w{type state tags}
    
    # The sha for self, set by the repo when convenient (for example by read).
    attr_accessor :sha
    
    # A hash of attributes for self
    attr_reader :attributes
    
    # The content for self
    attr_reader :content
    
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
      @attributes = attrs
      @attributes.delete_if {|key, value| empty?(value) }
      
      self[AUTHOR] = attrs[AUTHOR]
      self[DATE]   = attrs[DATE]
      self[TAGS]   = attrs[TAGS]
      
      @content = content
      @sha = sha
    end
    
    # Gets an attribute.
    def [](key)
      attributes[key]
    end
    
    # Sets an attribute.  Author and date attributes are parsed and validated.
    # Nil and empty values remove the attribute.
    # 
    # ==== Author and Date
    #
    # Author can be specified as a Grit::Actor or as a string in the standard
    # author format.  Author may not be set to nil.
    #
    # Date can be specified as a Time, a numeric, or a string in the standard
    # date format. Date may not be set to nil.
    def []=(key, value)
      value = case key
      when AUTHOR then parse_author(value)
      when DATE   then parse_date(value)
      when TAGS   then parse_tags(value)
      else value
      end
      
      if empty?(value)
        attributes.delete(key)
      else
        attributes[key] = value
      end
    end
    
    # Returns the author as set in attributes.
    def author
      attributes[AUTHOR]
    end
    
    # Returns the date as set in attributes.
    def date
      attributes[DATE]
    end
    
    # Returns the tags as set in attributes, or an empty array if no tags are
    # set.
    def tags
      attributes[TAGS] || []
    end
    
    # Yields each attribute to the block, sorted by key.
    def each_pair
      attributes.keys.sort!.each do |key|
        yield(key, attributes[key])
      end
    end
    
    # Yields each indexed key-value pair to the block.
    def each_index
      INDEX_KEYS.each do |key|
        next unless value = attributes[key]
        
        if value.respond_to?(:each)
          value.each {|val| yield(key, val) }
        else
          yield(key, value)
        end
      end
      
      email = author.email
      yield(AUTHOR, email)
      
      self
    end
    
    # Merges the attributes and content with self to produce a new Document.
    # If content is nil, then the content for self will be used.
    def merge(attrs, content=nil)
      Document.new(attributes.merge(attrs), content || self.content)
    end
    
    # Returns a hash of differences in the attributes of self and parent. 
    # Added and modified attributes will be keyed by strings and removes are
    # keyed by symbols.  Keys to skip can be specified by exclude.
    def diff(parent, *exclude)
      return attributes.dup unless parent
      
      current = attributes
      previous = parent.attributes
      keys = (current.keys + previous.keys - exclude).uniq
      
      diff = {}
      keys.each do |key|
        current_value  = current[key]
        previous_value = previous[key]
        next if current_value == previous_value
        
        if current.has_key?(key)
          # added or modified
          diff[key.to_s] = current[key]
        else
          # removed
          diff[key.to_sym] = previous[key]
        end
      end
      
      diff
    end
    
    # Serializes self into a string according to the document format.
    def to_s
      attrs = attributes.merge(
        AUTHOR => "#{author.name} <#{author.email}>",
        DATE   => date.to_f
      ).extend(SortedToYaml)
      
      "#{attrs.to_yaml}--- \n#{content}"
    end
    
    protected
    
    def empty?(value) # :nodoc:
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
    
    # helper to parse/validate an author
    def parse_author(author) # :nodoc:
      case author
      when String
        Grit::Actor.from_string(author)
      when nil
        raise "author cannot be nil"
      else
        author
      end
    end
    
    # helper to parse/validate a date
    def parse_date(date) # :nodoc:
      case date
      when Numeric
        Time.at(date)
      when String
        Time.at(date.to_f)
      when nil
        raise "date cannot be nil"
      else
        date
      end
    end
    
    # helper to parse/validate tags
    def parse_tags(tags) # :nodoc:
      unless tags.kind_of?(Array)
        tags = Shellwords.shellwords(tags.to_s)
      end
      
      tags.empty? ? nil : tags
    end
    
    # Raised by Document.parse for an invalid document.
    class InvalidDocumentError < StandardError
    end
    
    # A module to replace the Hash#to_yaml function to serialize with sorted keys.
    #
    # From: http://snippets.dzone.com/posts/show/5811
    # The original function is in: /usr/lib/ruby/1.8/yaml/rubytypes.rb
    #
    module SortedToYaml # :nodoc:
      def to_yaml( opts = {} )
        YAML::quick_emit( object_id, opts ) do |out|
          out.map( taguri, to_yaml_style ) do |map|
            sort.each do |k, v|
              map.add( k, v )
            end
          end
        end
      end
    end
  end
end