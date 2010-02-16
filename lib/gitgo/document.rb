require 'gitgo/repo'
require 'gitgo/document/utils'
require 'gitgo/document/invalid_document_error'

module Gitgo
  class Document
    ENV  = 'gitgo.env'
    REPO = 'gitgo.repo'
    
    class << self
      attr_reader :types
      attr_reader :validators
      
      def inherited(base)
        base.instance_variable_set(:@validators, validators.dup)
        base.instance_variable_set(:@types, types)
        base.register_as base.to_s.split('::').last.downcase
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
      
      def idx
        repo.idx
      end
      
      def type
        types[self]
      end
      
      def create(attrs={})
        doc = new(attrs, env)
        doc.save
        doc
      end
      
      def read(sha)
        sha = repo.resolve(sha)
        attrs = repo.read(sha)
        
        cast(attrs, sha)
      end
      
      def cast(attrs, sha)
        type = attrs['type']
        klass = types[type] or raise "unknown type: #{type}"
        klass.new(attrs, env, sha)
      end
      
      def update(sha, attrs={})
        doc = read(sha).merge!(attrs)
        doc.update
        doc
      end
      
      def find(criteria={}, update_idx=true)
        self.update_idx if update_idx
        
        # use type to determine basis -- note that idx.all('email') should
        # return all documents because all documents should have an email
        basis = type ? idx.get('type', type) : idx.all('email')
        idx.select(basis, criteria).collect! {|sha| self[sha] }
      end
      
      def update_idx(reindex=false)
        idx = self.idx
        idx.clear if reindex
        repo_head, idx_head = repo.head, idx.head
        
        if repo_head.nil? || repo_head == idx_head
          return []
        end
        
        shas = repo.diff(idx_head, repo_head)
        shas.each do |sha|
          self[sha].each_index do |key, value|
            idx.add(key, value, sha)
          end
        end
        
        idx.write(repo.head)
        shas
      end
      
      def [](sha)
        cast(repo[sha], sha)
      end
      
      protected
      
      def register_as(type)
        types[type] = self
        types[self] = type
      end
      
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
    @types = {}
    register_as(nil)
    
    attr_reader :env
    attr_reader :attrs
    attr_accessor :sha
    
    define_attributes do
      attr_accessor(:author) {|author| validate_format(author, AUTHOR) }
      attr_accessor(:date)   {|date| validate_format(date, DATE) }
      attr_accessor(:re)     {|re| validate_format_or_nil(re, SHA) }
      attr_accessor(:at)     {|at| validate_format_or_nil(at, SHA) }
      attr_accessor(:tags)   {|tags| validate_array_or_nil(tags) }
      attr_writer(:parents)  {|parents| validate_array_or_nil(parents) }
      attr_writer(:children) {|children| validate_array_or_nil(children) }
      attr_accessor(:type)
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
    
    def origin=(sha)
      self.re = sha
    end
    
    def origin?
      re.nil?
    end
    
    def active?(commit=nil)
      return true if at.nil? || commit.nil?
      repo.rev_list(commit).include?(at)
    end
    
    def graph(reset=false)
      @graph = nil if reset
      @graph ||= (saved? ? repo.graph(origin) : nil)
    end
    
    def parents
      attrs['parents'] || (saved? ? graph.parents(sha) : nil)
    end
    
    def children
      attrs['children'] || (saved? ? graph.children(sha) : nil)
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
      
      unless type = attrs['type']
        default_type = self.class.type
        attrs['type'] = default_type if default_type
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
    
    def save(force=false)
      return sha if saved? && !force
      
      validate
      
      parents  = attrs.delete('parents')
      children = attrs.delete('children')
      
      self.sha = repo.store(attrs)
      parents.each {|parent| repo.link(parent, sha) } if parents
      children.each {|child| repo.link(sha, child) } if children
      each_index {|key, value| idx.add(key, value, sha) }
      
      sha
    end
    
    def saved?
      @sha.nil? ? false : true
    end
    
    def update(old_sha=sha)
      new_sha = save(true)
      
      unless old_sha.nil? || old_sha == new_sha
        repo.update(old_sha, new_sha)
      end
      
      new_sha
    end
    
    def indexes
      indexes = []
      each_index {|key, value| indexes << [key, value] }
      indexes
    end
    
    def each_index
      if author = attrs['author']
        actor = Grit::Actor.from_string(author)
        yield('email', blank?(actor.email) ? 'unknown' : actor.email)
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
        yield('tail', type) if saved? && repo.tail?(sha)
      end
      
      self
    end
    
    def initialize_copy(orig)
      super
      @attrs = orig.attrs.dup
      @graph = nil
      @sha = nil
    end
    
    def inspect
      "#<#{self.class}:#{object_id} sha=#{sha.inspect}>"
    end
  end
end