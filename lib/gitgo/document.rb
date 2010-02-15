require 'gitgo/repo'
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
    @define_attributes = false
    @validators = {}
    
    attr_reader :env
    attr_reader :attrs
    attr_accessor :sha
    
    define_attributes do
      attr_accessor :author
      attr_accessor :date
      attr_accessor :re
      attr_accessor :at
      attr_accessor :tags
      attr_writer :parents
      attr_writer :children
    end
    
    def initialize(attrs={}, env=nil, sha=nil)
      @env = env || self.class.env
      @attrs = attrs
      @sha = sha
    end
    
    def repo
      env[REPO]
    end
    
    def [](key)
      attrs[key]
    end
    
    def []=(key, value)
      attrs[key] = value
    end
    
    def merge(attrs)
      dup.merge!(attrs)
    end
    
    def merge!(attrs)
      self.attrs.merge!(attrs)
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
    
    def validate
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
      
      sha = repo.store(attrs)
      parents.each {|parent| repo.link(parent, sha) } if parents
      children.each {|child| repo.link(sha, child) } if children
      
      self.sha = sha
    end
    
    def saved?
      @sha.nil? ? false : true
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