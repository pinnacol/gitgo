require 'gitgo/repo'
require 'gitgo/document/utils'
require 'gitgo/document/invalid_document_error'

module Gitgo
  class Document
    ENV  = 'gitgo.env'
    REPO = 'gitgo.repo'
    
    class << self
      attr_reader :validators
      
      def inherited(base)
        base.instance_variable_set(:@validators, validators.dup)
      end
      
      def set_env(env)
        current = Thread.current[ENV]
        Thread.current[ENV] = env
        current
      end
      
      def with_env(env)
        begin
          current = set_env(env)
          yield
        ensure
          set_env(current)
        end
      end
      
      def env
        Thread.current[ENV] or raise("no env in scope")
      end
      
      def repo
        env[REPO] or raise("no repo in env")
      end
      
      protected
      
      def define_attributes(&block)
        begin
          @define_attributes = true
          instance_eval(&block)
        ensure
          @define_attributes = false
        end
      end
      
      def attr_reader(*keys)
        return super unless @define_attributes
        keys.each do |key|
          key = key.to_s
          define_method(key) { attrs[key] }
        end
      end
      
      def attr_writer(*keys, &block)
        return super unless @define_attributes
        keys.each do |key|
          key = key.to_s
          define_method("#{key}=") {|value| attrs[key] = value }
          validate(key, &block) if block_given?
        end
      end
      
      def attr_accessor(*keys, &block)
        return super unless @define_attributes
        attr_reader(*keys)
        attr_writer(*keys, &block)
      end
      
      def validate(key, validator="validate_#{key}", &block)
        validators[key.to_s] = validator.to_sym
        define_method(validator, &block) if block_given?
      end
    end
    include Utils
    
    @define_attributes = false
    @validators = {}
    
    attr_reader :env
    attr_reader :attrs
    attr_accessor :sha
    
    define_attributes do
      attr_accessor(:author) {|author| validate_format(author, AUTHOR) }
      attr_accessor(:date)   {|date| validate_format(date, DATE) }
      attr_accessor(:re)     {|re| validate_format_or_nil(re, SHA) }
      attr_accessor(:at)     {|at| validate_format_or_nil(at, SHA) }
      attr_accessor(:tags)   {|tags| validate_array_or_nil(tags) }
      attr_accessor(:parents)  {|parents| validate_array_or_nil(parents) }
      attr_accessor(:children) {|children| validate_array_or_nil(children) }
    end
    
    def initialize(attrs={}, env=nil, sha=nil)
      @env = env || self.class.env
      @attrs = attrs
      @sha = sha
    end
    
    def repo
      env[REPO]
    end
    
    def idx
      repo.idx
    end
    
    def [](key)
      attrs[key]
    end
    
    def []=(key, value)
      attrs[key] = value
    end
    
    def origin
      re || sha
    end
        
    def origin?
      re.nil?
    end
    
    def merge(attrs)
      dup.merge!(attrs)
    end
    
    def merge!(attrs)
      self.attrs.merge!(attrs)
      self
    end
    
    def normalize
      dup.normalize!
    end
    
    def normalize!
      attrs['author'] ||= begin
        author = repo.author
        "#{author.name} <#{author.email}>"
      end
      
      attrs['date'] ||= Time.now.iso8601
      
      if re = attrs['re']
        attrs['re'] = repo.resolve(re)
      end
      
      if at = attrs['at']
        attrs['at'] = repo.resolve(at)
      end
      
      if parents = attrs['parents']
        parents = arrayify(parents)
        attrs['parents'] = parents.collect {|parent| repo.resolve(parent) }
      end
      
      if children = attrs['children']
        children = arrayify(children)
        attrs['children'] = children.collect {|child| repo.resolve(child) }
      end
      
      if tags = attrs['tags']
        attrs['tags'] = arrayify(tags)
      end
      self
    end
    
    def errors
      errors = {}
      self.class.validators.each_pair do |key, validator|
        begin
          send(validator, attrs[key])
        rescue
          errors[key] = $!
        end
      end
      errors
    end
    
    def validate(normalize=true)
      normalize! if normalize
      
      errors = self.errors
      unless errors.empty?
        raise InvalidDocumentError.new(self, errors)
      end
      self
    end
    
    def save
      validate
      
      parents  = attrs.delete('parents')
      children = attrs.delete('children')
      
      self.sha = repo.store(attrs)
      parents.each {|parent| repo.link(parent, sha) } if parents
      children.each {|child| repo.link(sha, child) } if children
      each_index {|key, value| idx.add(key, value, sha) }
      
      self
    end
    
    def saved?
      @sha.nil? ? false : true
    end
    
    def each_index
      if author = attrs['author']
        actor = Grit::Actor.from_string(author)
        yield('email', actor.email)
      end
      
      if re = attrs['re']
        yield('re', re)
      end
      
      if at = attrs['at']
        yield('at', at)
      end
      
      if tags = attrs['tags']
        tags.each do |tag|
          yield('tags', tag)
        end
      end
      
      if type = attrs['type']
        yield('type', type) if origin?
        yield('tail', type) if saved? && tail?(sha)
      end
      
      self
    end
    
    def initialize_copy(orig)
      super
      @attrs = orig.attrs.dup
      @sha = nil
    end
    
    def inspect
      "#<#{self.class}:#{object_id} sha=#{sha.inspect}>"
    end
  end
end