module Gitgo
  class Index
    include Enumerable
    
    attr_reader :store, :block, :cache
    
    def initialize(store={}, &block)
      @store = store
      @block = block
      @cache = {}
    end
    
    def [](key)
      store[key]
    end
    
    def []=(key, docs)
      store[key] = docs
    end
    
    def query(key)
      cache[key] ||= yield
    end
    
    def update(key)
      store[key] = block.call(key)
      cache.clear
    end
    
    # Yields each doc to the block
    def each
      store.each_value do |docs|
        docs.each do |doc|
          yield(doc)
        end
      end
    end
    
    # Returns keys for store.  A block may be given to select only keys
    # where one of it's docs satisfies the block.
    #
    #   index.keys {|doc| doc['state'] == 'open' }
    #
    def keys # :yields: doc
      return store.keys unless block_given?
      
      selected = []
      store.each_pair do |key, docs|
        if docs.any? {|doc| yield(doc) }
          selected << key
        end
      end
      selected
    end
  end
end