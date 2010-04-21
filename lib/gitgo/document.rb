require 'gitgo/repo'
require 'gitgo/document/utils'
require 'gitgo/document/invalid_document_error'

module Gitgo
  
  # Document represents the data model of Gitgo, and provides high-level
  # access to documents stored in a Repo.  Content and data consistentcy
  # constraints are enforced on Document.
  #
  class Document
    class << self
      
      # Returns a hash registry mapping a type string to a Document class.
      # Document itself is registered as the nil type.  Types also includes
      # reverse mappings for a Document class to it's type string.
      attr_reader :types
      
      # A hash of (key, validator) pairs mapping attribute keys to a
      # validation method.  Not all attributes will have a validator whereas
      # some attributes share the same validation method.
      attr_reader :validators
      
      def inherited(base) # :nodoc:
        base.instance_variable_set(:@validators, validators.dup)
        base.instance_variable_set(:@types, types)
        base.register_as base.to_s.split('::').last.downcase
      end
      
      # Returns the Repo currently in scope (see Repo.current)
      def repo
        Repo.current
      end
      
      # Returns the index on repo.
      def index
        repo.index
      end
      
      # Returns the type string for self.
      def type
        types[self]
      end
      
      # Creates, links, and indexes a new document.  The new document is
      # returned. The 'parent' and 'children' attributes specify the document
      # links and, if present, will not be stored in the document itself.
      #
      # Returns the new document.
      def create(attrs={})
        parents = attrs.delete('parents')
        children = attrs.delete('children')
        
        doc = new(attrs, repo)
        doc.save
        doc.link(parents, children)
        doc.reindex
        doc
      end
      
      # Reads the specified document and casts it into an instance as per
      # cast.  Returns nil if the document doesn't exist.
      #
      # Read will re-read the document directly from the git repository every
      # time it is called.  For better performance, use the AGET method which
      # performs the same read but uses the Repo cache if possible.
      def read(sha)
        sha = repo.resolve(sha)
        attrs = repo.read(sha)
        
        attrs ? cast(attrs, sha) : nil
      end
      
      # Reads the specified document from the repo cache and casts it into an
      # instance as per cast.  Returns nil if the document doesn't exist.
      def [](sha)
        sha = repo.resolve(sha)
        cast(repo[sha], sha)
      end
      
      # Casts the attributes hash into a document instance.  The document
      # class is determined by resolving the 'type' attribute against the
      # types registry.
      def cast(attrs, sha)
        type = attrs['type']
        klass = types[type] or raise "unknown type: #{type}"
        klass.new(attrs, repo, sha)
      end
      
      # Updates and indexes the specified document with new attributes.  The
      # new attributes are merged with the existing attributes.  New linkages
      # cannot be specified with this method.
      def update(sha, attrs={})
        sha = sha.sha if sha.respond_to?(:sha)
        doc = read(sha).merge!(attrs)
        doc.update
        doc.reindex
        doc
      end
      
      # Finds all documents matching the any and all criteria.  The any and
      # all inputs are hashes of index values used to filter all possible
      # documents. They consist of (key, value) or (key, [values]) pairs, at
      # least one of which must match in the any case, all of which must match
      # in the all case.  Specify nil for either array to prevent filtering
      # using that criteria.
      #
      # See basis for more detail regarding the scope of 'all documents' that
      # can be found via find.
      #
      # If update_index is specified, then the document index will be updated
      # before the find is performed.  Typically update_index should be
      # specified to true to capture any new documents added, for instance by
      # a merge; it adds little overhead in the most common case where the
      # index is already up-to-date.
      def find(all={}, any=nil, update_index=true)
        self.update_index if update_index
        index.select(
          :basis => basis, 
          :all => all, 
          :any => any, 
          :shas => true
        ).collect! {|sha| self[sha] }
      end
      
      # Performs a partial update of the document index.  All documents added
      # between the index-head and the repo-head are updated using this
      # method.
      #
      # Specify reindex to clobber and completely rebuild the index.
      def update_index(reindex=false)
        index.clear if reindex
        repo_head, index_head = repo.head, index.head
        
        # if the index is up-to-date save the work of doing diff
        if repo_head.nil? || repo_head == index_head
          return []
        end
        
        shas = repo.diff(index_head, repo_head)
        shas.each {|sha| self[sha].reindex }
        
        index.write(repo.head)
        shas
      end
      
      protected
      
      # Returns the basis for finds, ie the set of documents that get filtered
      # by the find method.  
      #
      # If type is specified for self, then only documents of type will be
      # available (ie Issue.find will only find documents of type 'issue'). 
      # Document itself will filter all documents with an email; which should
      # typically represent all possible documents.
      def basis
        type ? index['type'][type] : index.all('email')
      end
      
      # Registers self as the specified type.  The previous registered type is
      # overridden.
      def register_as(type)
        types.delete_if {|key, value| key == self || value == self }
        types[type] = self
        types[self] = type
      end
      
      # Turns on attribute definition for the duration of the block.  If
      # attribute definition is on, then the standard attribute declarations
      # (attr_reader, attr_writer, attr_accessor) will create accessors for
      # the attrs hash rather than instance variables.
      #
      # Moreover, blocks given to attr_writer/attr_accessor will be used to
      # define a validator for the accessor.
      def define_attributes(&block)
        begin
          @define_attributes = true
          instance_eval(&block)
        ensure
          @define_attributes = false
        end
      end
      
      def attr_reader(*keys) # :nodoc:
        return super unless @define_attributes
        keys.each do |key|
          key = key.to_s
          define_method(key) { attrs[key] }
        end
      end
      
      def attr_writer(*keys, &block) # :nodoc:
        return super unless @define_attributes
        keys.each do |key|
          key = key.to_s
          define_method("#{key}=") {|value| attrs[key] = value }
          validate(key, &block) if block_given?
        end
      end
      
      def attr_accessor(*keys, &block) # :nodoc:
        return super unless @define_attributes
        attr_reader(*keys)
        attr_writer(*keys, &block)
      end
      
      # Registers the validator method to validate the specified attribute. If
      # a block is given, it will be used to define the validator as a
      # protected instance method (otherwise you need to define the validator
      # method manually).
      def validate(key, validator="validate_#{key}", &block)
        validators[key.to_s] = validator.to_sym
        
        if block_given?
          define_method(validator, &block)
          protected validator
        end
      end
    end
    include Utils
    
    @define_attributes = false
    @validators = {}
    @types = {}
    register_as(nil)
    
    # The repo this document belongs to.
    attr_reader :repo
    
    # A hash of the document attributes, corresponding to what is stored in
    # the repo.
    attr_reader :attrs
    
    # The document sha, unset until the document is saved.
    attr_reader :sha
    
    validate(:author) {|author| validate_format(author, AUTHOR) }
    validate(:date)   {|date|   validate_format(date, DATE) }
    validate(:origin) {|origin| validate_format_or_nil(origin, SHA) }
    
    define_attributes do
      attr_accessor(:at)   {|at|   validate_format_or_nil(at, SHA) }
      attr_writer(:tags)   {|tags| validate_array_or_nil(tags) }
      attr_accessor(:type)
    end
    
    def initialize(attrs={}, repo=nil, sha=nil)
      @repo = repo || Repo.current
      @attrs = attrs
      reset(sha)
    end
    
    # Returns the repo index.
    def index
      repo.index
    end
    
    def idx
      index.idx(sha)
    end
    
    # Gets the specified attribute.
    def [](key)
      attrs[key]
    end
    
    # Sets the specified attribute.
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
      self['origin'] || sha
    end
    
    def origin=(sha)
      self['origin'] = sha
      reset
    end
    
    def origin?
      self['origin'].nil?
    end
    
    def active?(commit=nil)
      return true if at.nil? || commit.nil?
      repo.rev_list(commit).include?(at)
    end
    
    def detached?
      node.nil?
    end
    
    def node
      graph[sha]
    end
    
    def graph
      @graph ||= repo.graph(repo.resolve(origin))
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
        attrs['origin'] = repo.resolve(origin)
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
      self
    end
    
    def saved?
      sha.nil? ? false : true
    end
    
    def update(old_sha=sha)
      old_sha = repo.resolve(old_sha)
      reset old_sha
      
      validate
      reset repo.store(attrs, date)
      
      unless old_sha.nil? || old_sha == sha
        repo.update(old_sha, sha)
        tail_filter(old_sha)
      end
      
      self
    end
    
    def link(parents=nil, children=nil)
      raise "cannot link unless saved" unless saved?
      
      parents  = validate_links(parents)
      children = validate_links(children)
      
      parents.each {|parent| repo.link(parent, sha) }
      children.each {|child| repo.link(sha, child) }
      
      tail_filter *parents
      tail_filter sha unless children.empty?
      
      reset(sha)
      self
    end
    
    def reindex
      raise "cannot reindex unless saved" unless saved?
      
      idx = index.idx(sha)
      each_index {|key, value| index[key][value] << idx }
      index.map[idx] = index.idx(origin)
      
      if node && !node.tail?
        tail_filter(sha)
      end
      
      self
    end
    
    def reset(new_sha=sha)
      @graph = nil
      @sha = new_sha
      self
    end
    
    def commit!
      repo.commit!
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
    
    def tail_filter(*shas) # :nodoc:
      shas.collect! {|sha| index.idx(sha) }
      index['filter']['tail'].concat(shas)
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