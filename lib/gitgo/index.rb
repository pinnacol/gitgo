module Gitgo
  
  # Index is a structure for storing parent-child relationships and making
  # queries across those relationships.  Index is used by Issues to generate
  # and store state information.
  class Index
    include Enumerable
    
    # The internal storage for parent-child relationships.  Store
    # is a hash of (parent, children) pairs.
    attr_reader :store
    
    # A block used to update the children for a parent.
    attr_reader :block
    
    # A cache of query results.
    attr_reader :cache
    
    def initialize(store={}, &block)
      @store = store
      @block = block
      @cache = {}
    end
    
    # Gets the children for the parent.
    def [](parent)
      store[parent]
    end
    
    # Sets the children for the parent.
    def []=(parent, children)
      store[parent] = children
    end
    
    def query(name, parent=nil)
      cache["#{name}#{parent}"] ||= yield
    end
    
    def update(parent)
      store[parent] = block.call(parent)
      cache.clear
    end
    
    # Yields each obj to the block
    def each(key=nil)
      store.each_pair do |key, keys|
        yield(key)
        keys.each {|key| yield(key) }
      end
    end
    
    # Returns keys for store.  A block may be given to select only keys
    # where one of it's docs satisfies the block.
    #
    #   index.keys {|doc| doc['state'] == 'open' }
    #
    def select_keys # :yields: doc
      return store.keys unless block_given?
      
      selected = []
      store.each_pair do |key, objects|
        if objects.any? {|obj| yield(obj) }
          selected << key
        end
      end
      selected
    end
  end
end