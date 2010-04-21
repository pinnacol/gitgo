require 'enumerator'
require 'gitgo/index/index_file'

module Gitgo
  
  # Index provides an index of documents used to expedite searches.  Index
  # structures it's data into a branch-specific directory structure:
  #
  #   .git/gitgo/refs/[branch]/index
  #   |- doc
  #   |  `- key
  #   |     `- value
  #   |
  #   |- head
  #   |- list
  #   `- map
  #
  # The files contain the following data (in conceptual order):
  #
  #   head      The user commit sha at which the last reindex occured.
  #   list      A list of H* packed shas representing all of the documents
  #             accessible by the gitgo branch. The index of the sha in list
  #             serves as an identifier for the sha in map and filters.
  #   map       A list of L* packed identifier pairs mapping a document to
  #             its graph head.
  #   [value]   A list of L* packed identifiers that match the key-value
  #             pair.  These lists act as filters in searches.
  #
  # The packing format for each of the index files was chosen for performance;
  # both to minimize the footprint of the file and optimize the usage of the
  # file data.
  #
  # Index also maintains a cache of temporary files that auto-expire after a
  # certain period of time.  The temporary files contain H* packed shas and
  # represent the results of various queries, such as rev-lists.
  #
  # == Usage
  #
  # Index files are used primarily to select documents based on various
  # filters. For example, to select the shas for all comments tagged as
  # 'important' you would do this:
  #
  #   index = Index.new('path')
  #
  #   comment   = index['type']['comment']
  #   important = index['tag']['important']
  #   selected  = comment & important
  #
  #   heads = selected.collect {|id| idx.map[id] }
  #   shas  = heads.collect {|id| idx.list[id] }.uniq
  #
  # The array operations are very quick because the filters are composed of
  # integers, as is the map.  The final step looks up the shas, but this too
  # is simply an array lookup.
  #
  # Importantly the index files can all contain duplication without affecting
  # the results of the select procedure; this allows new documents to be
  # quickly added into a filter, or appended to list/map. As needed or
  # convenient, the index can take the time to compact itself and remove
  # duplication.
  #
  class Index
    
    # A file containing the ref at which the last index was performed; used to
    # determine when a reindex is required relative to some other ref.
    HEAD = 'head'
    
    # A file mapping shas to their origins like: sha,origin,sha,origin
    MAP = 'map'
    
    # The head file for self
    attr_reader :head_file
    
    # The map file for self
    attr_reader :map_file
    
    # Returns an in-memory, self-filling cache of index files
    attr_reader :cache
    
    # References a string table that acts like a symbol table, but for shas.
    attr_reader :string_table
    
    def initialize(path, string_table=nil)
      @path = path
      @head_file = File.expand_path(HEAD, path)
      @map_file = File.expand_path(MAP, path)
      @string_table = string_table
      
      @cache = Hash.new do |key_hash, key|
        key_hash[key] = Hash.new do |value_hash, value|
          value_hash[value] = begin
            index = self.path(key, value)
            values = File.exists?(index) ? IndexFile.read(index) : []
            stringify(values)
          end
        end
      end
    end
    
    # Returns the sha in the head_file, if it exists, and nil otherwise.
    def head
      File.exists?(head_file) ? File.open(head_file) {|io| io.read(40) } : nil
    end
    
    # Returns the contents of map_file, as a hash.
    def map
      @map ||= begin
        map = {}
        array = File.exists?(map_file) ? IndexFile.read(map_file) : []
        stringify(array).each_slice(2) {|sha, origin| map[sha] = origin }
        map
      end
    end
    
    # Returns the tail filter.
    def filter
      self['tail']['filter']
    end
    
    # Returns the segments joined to the path used to initialize self.
    def path(*segments)
      segments.collect! {|segment| segment.to_s }
      File.join(@path, *segments)
    end
    
    #--
    # note be careful not to modify idx[k][v], it is the actual storage
    def [](key)
      cache[key]
    end
    
    def get(key, value)
      cache[key][value].dup
    end
    
    def set(key, value, *shas)
      cache[key][value] = shas
      self
    end
    
    def add(key, value, sha)
      cache[key][value] << sha
      self
    end
    
    def rm(key, value, sha)
      cache[key][value].delete(sha)
      self
    end
    
    # Returns a list of possible index keys.
    def keys
      keys = cache.keys
      
      Dir.glob(path("*")).select do |path|
        File.directory?(path)
      end.each do |path|
        keys << File.basename(path)
      end
      
      keys.uniq!
      keys
    end
    
    # Returns a list of possible values for the specified index key.
    def values(key)
      values = cache[key].keys
      
      base = path(key)
      start = base.length + 1
      Dir.glob("#{base}/**/*").each do |path|
        values << path[start, path.length-start]
      end
      
      values.uniq!
      values
    end
    
    def all(*keys)
      results = []
      keys.collect do |key|
        values(key).each do |value|
          results.concat(cache[key][value])
        end
      end
      results.uniq!
      results
    end
    
    def join(key, *values)
      values.collect {|value| cache[key][value] }.flatten
    end
    
    def select(shas, all=nil, any=nil)
      if all
        each_pair(all) do |key, value|
          shas = shas & cache[key][value]
          break if shas.empty?
        end
      end
      
      if any
        matches = []
        each_pair(any) do |key, value|
          matches.concat cache[key][value]
        end
        shas = shas & matches
      end
      
      shas
    end
    
    def clean
      @cache.values.each do |value_hash|
        value_hash.values.each do |shas|
          shas.uniq!
        end
      end
      self
    end
    
    # Writes cached changes.
    def write(sha=nil)
      clean
      
      @cache.each_pair do |key, value_hash|
        value_hash.each_pair do |value, shas|
          IndexFile.write(path(key, value), shas.join)
        end
      end
      
      FileUtils.mkdir_p(path) unless File.exists?(path)
      File.open(head_file, "w") {|io| io.write(sha) } if sha
      IndexFile.write(map_file, map.to_a.join)
      
      self
    end
    
    # Clears the cache.
    def reset
      @map = nil
      @cache.clear
      self
    end
    
    # Clears all index files, and the cache.
    def clear
      if File.exists?(path)
        FileUtils.rm_r(path)
      end
      reset
    end
    
    private
    
    def each_pair(pairs) # :nodoc:
      pairs.each_pair do |key, values|
        unless values.kind_of?(Array)
          values = [values]
        end
        
        values.each do |value|
          yield(key, value)
        end
      end
    end
    
    def stringify(array) # :nodoc:
      array.collect! {|str| string_table[str.to_s] } if string_table
      array
    end
  end
end