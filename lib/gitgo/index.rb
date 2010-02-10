require 'gitgo/index/index_file'

module Gitgo
  class Index
    
    # A file containing the ref at which the last index was performed; used to
    # determine when a reindex is required relative to some other ref.
    HEAD = 'head'
    
    attr_reader :head_file
    
    # Returns an in-memory cache of index files
    attr_reader :cache
    
    def initialize(path)
      @path = path
      @head_file = File.expand_path(HEAD, path)
      
      @cache = Hash.new do |key_hash, key|
        key_hash[key] = Hash.new do |value_hash, value|
          value_hash[value] = begin
            index = self.path(key, value)
            File.exists?(index) ? IndexFile.read(index) : []
          end
        end
      end
    end
    
    # Returns the sha in the head_file, if it exists, and nil otherwise.
    def head
      File.exists?(head_file) ? File.open(head_file) {|io| io.read(40) } : nil
    end
    
    # Returns the segments joined to the path used to initialize self.
    def path(*segments)
      segments.collect! {|segment| segment.to_s }
      File.join(@path, *segments)
    end
    
    def [](key)
      cache[key]
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
    
    def select(shas, criteria={})
      criteria.each_pair do |key, values|
        shas = shas & join(key, *values)
        break if shas.empty?
      end
      
      shas
    end
    
    def filter(shas, criteria={})
      criteria.each_pair do |key, values|
        shas -= join(key, *values)
        break if shas.empty?
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
    def write(sha)
      clean
      
      @cache.each_pair do |key, value_hash|
        value_hash.each_pair do |value, shas|
          IndexFile.write(path(key, value), shas.join)
        end
      end
      
      FileUtils.mkdir_p(path) unless File.exists?(path)
      File.open(head_file, "w") {|io| io.write(sha) }
      
      self
    end
    
    # Clears the cache.
    def reset
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
  end
end