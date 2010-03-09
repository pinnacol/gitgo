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
      
      def idx
        repo.idx
      end
      
      def type
        types[self]
      end
      
      def create(attrs={})
        parents = attrs.delete('parents')
        children = attrs.delete('children')
        
        doc = new(attrs, repo)
        doc.save
        doc.link(parents, children)
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
        sha = sha.sha if sha.respond_to?(:sha)
        doc = read(sha).merge!(attrs)
        doc.update
        doc
      end
      
      def find(all={}, any=nil, update_idx=true)
        self.update_idx if update_idx
        
        # use type to determine basis -- note that idx.all('email') should
        # return all documents because all documents should have an email
        shas = (all ? all.delete('shas') : nil) || basis
        shas = [shas] unless shas.kind_of?(Array)
        
        idx.select(shas, all, any).collect! {|sha| self[sha] }
      end
      
      def basis
        type ? idx.get('type', type) : idx.all('email')
      end
      
      def update_idx(reindex=false)
        idx.clear if reindex
        repo_head, idx_head = repo.head, idx.head
        
        if repo_head.nil? || repo_head == idx_head
          return []
        end
        
        shas = repo.diff(idx_head, repo_head)
        shas.each {|sha| self[sha].reindex }
        
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
    attr_reader :sha
    
    validate(:author) {|author| validate_format(author, AUTHOR) }
    validate(:date)   {|date| validate_format(date, DATE) }
    validate(:origin) {|origin| validate_format_or_nil(origin, SHA) }
    
    define_attributes do
      attr_accessor(:at)   {|at| validate_format_or_nil(at, SHA) }
      attr_writer(:tags)   {|tags| validate_array_or_nil(tags) }
      attr_accessor(:type)
    end
    
    def initialize(attrs={}, repo=nil, sha=nil)
      @repo = repo || Repo.current
      @attrs = attrs
      reset(sha)
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
      self['author'] = author
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
      self['date'] = date
    end
    
    def date(cast=true)
      date = attrs['date']
      if cast && date.kind_of?(String)
        date = Time.parse(date)
      end
      date
    end
    
    def origin
      self['origin'] || (sha ? repo.original(sha) : nil)
    end
    
    def origin=(sha)
      self['origin'] = sha
      reset
    end
    
    def origin?
      self['origin'].nil?
    end
    
    def original?
      repo.original?(sha)
    end
    
    def current?
      repo.current?(sha)
    end
    
    def tail?
      repo.tail?(sha)
    end
    
    def active?(commit=nil)
      return true if at.nil? || commit.nil?
      repo.rev_list(commit).include?(at)
    end
    
    def graph
      @graph ||= repo.graph(resolve origin)
    end
    
    def parents
      graph.parents(sha)
    end
    
    def children
      graph.children(sha)
    end
    
    def tags
      self['tags'] ||= []
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
      
      if origin = attrs['origin']
        attrs['origin'] = resolve(origin)
      end
      
      if at = attrs['at']
        attrs['at'] = repo.resolve(at)
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
      
      if origin = attrs['origin']
        yield('origin', origin)
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
        yield('type', type)
      end
      
      self
    end
    
    def save
      validate
      reset repo.store(attrs, date)
      reindex
      self
    end
    
    def saved?
      sha.nil? ? false : true
    end
    
    def update(old_sha=sha)
      old_sha = resolve(old_sha)
      reset old_sha
      
      validate
      reset repo.store(attrs, date)
      
      unless old_sha.nil? || old_sha == sha
        repo.update(old_sha, sha)
        idx.filter << old_sha
      end
      
      reindex
      self
    end
    
    def link(parents=nil, children=nil)
      raise "cannot link unless saved" unless saved?
      
      parents  = validate_links(parents)
      children = validate_links(children)
      
      parents.each {|parent| repo.link(parent, sha) }
      children.each {|child| repo.link(sha, child) }
      
      idx.filter.concat(parents)
      idx.filter << sha unless children.empty?
      
      reset(sha)
      self
    end
    
    def reindex
      raise "cannot reindex unless saved" unless saved?
      
      idx = self.idx
      each_index {|key, value| idx.add(key, value, sha) }
      idx.map[sha] = origin
      idx.filter << sha unless repo.tail?(sha)
      
      self
    end
    
    def reset(new_sha=sha)
      @graph = nil
      @sha = new_sha
      self
    end
    
    def initialize_copy(orig)
      super
      reset(nil)
      @attrs = orig.attrs.dup
    end
    
    def inspect
      "#<#{self.class}:#{object_id} sha=#{sha.inspect}>"
    end
    
    # This is a thin equality -- use with caution.
    def ==(another)
      saved? ? sha == another.sha : super
    end
    
    protected
    
    def resolve(ref) # :nodoc:
      ref = ref.sha if ref.respond_to?(:sha)
      repo.resolve(ref)
    end
    
    def validate_links(links) # :nodoc:
      arrayify(links).collect do |doc|
        unless doc.kind_of?(Document)
          doc = repo.resolve(doc)
          doc = Document[doc]
        end
        
        validate_origins(doc, self)
        doc.sha
      end
    end
  end
end