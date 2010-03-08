require 'gitgo/repo'
require 'gitgo/document/utils'
require 'gitgo/document/invalid_document_error'

module Gitgo
  class Document
    class << self
      attr_reader :types
      attr_reader :validators
      
      def inherited(base)
        base.instance_variable_set(:@validators, validators.dup)
        base.instance_variable_set(:@types, types)
        base.register_as base.to_s.split('::').last.downcase
      end
      
      def repo
        Repo.current
      end
      
      def type
        types[self]
      end
      
      def create(attrs={})
        doc = new(attrs, repo)
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
        klass.new(attrs, repo, sha)
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
        idx = repo.idx
        basis = type ? idx.get('type', type) : idx.all('email')
        idx.select(basis, criteria).collect! {|sha| self[sha] }
      end
      
      def update_idx(reindex=false)
        idx = repo.idx
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
    
    attr_reader :repo
    attr_reader :attrs
    attr_accessor :sha
    
    validate(:author) {|author| validate_format(author, AUTHOR) }
    validate(:date)   {|date| validate_format(date, DATE) }
    
    define_attributes do
      attr_accessor(:re)   {|re| validate_format_or_nil(re, SHA) }
      attr_accessor(:at)   {|at| validate_format_or_nil(at, SHA) }
      attr_accessor(:tags) {|tags| validate_array_or_nil(tags) }
      
      attr_writer(:parents) do |parents|
        validate_array_or_nil(parents)
        parents.each do |parent|
          validate_origins(Document[parent], self)
        end if parents
      end
      
      attr_writer(:children) do |children|
        validate_array_or_nil(children)
        children.each do |child|
          validate_origins(self, Document[child])
        end if children
      end
      
      attr_accessor(:type)
    end
    
    def initialize(attrs={}, repo=nil, sha=nil)
      @repo = repo || Repo.current
      @attrs = attrs
      @sha = sha
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
    
    def author=(author)
      if author.kind_of?(Grit::Actor)
        author = author.email ? "#{author.name} <#{author.email}>" : author.name
      end
      attrs['author'] = author
    end
    
    def author(cast=true)
      author = attrs['author']
      if cast && author.kind_of?(String)
        author = Grit::Actor.from_string(author)
      end
      author
    end
    
    def date=(date)
      if date.respond_to?(:iso8601)
        date = date.iso8601
      end
      attrs['date'] = date
    end
    
    def date(cast=true)
      date = attrs['date']
      if cast && date.kind_of?(String)
        date = Time.parse(date)
      end
      date
    end
    
    def origin
      re || (sha ? repo.original(sha) : nil)
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
    
    def tail?(reset=false)
      return false unless g = graph(reset)
      g.tail?(sha) && g.current?(sha)
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
      children.each {|child| repo.link(sha, child) }  if children
      each_index {|key, value| idx.add(key, value, sha) }
      
      sha
    end
    
    def saved?
      @sha.nil? ? false : true
    end
    
    def update(old_sha=sha)
      
      # ensure children of the old sha will be reassigned so as to properly
      # identify tails.  note that sha must be set to determine and validate
      # existing children
      self.sha = old_sha
      attrs['children'] ||= children
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