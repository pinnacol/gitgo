require 'enumerator'
require 'gitgo/index/idx_file'
require 'gitgo/index/sha_file'

module Gitgo
  
  # Index provides an index of documents used to expedite searches.  Index
  # structures it's data into a branch-specific directory structure:
  #
  #   .git/gitgo/refs/[branch]/index
  #   |- filter
  #   |  `- key
  #   |     `- value
  #   |
  #   |- head
  #   |- list
  #   `- graph_map
  #
  # The files contain the following data (in conceptual order):
  #
  #   head      The user commit sha at which the last reindex occured.
  #   list      A list of H* packed shas representing all of the documents
  #             accessible by the gitgo branch. The index (idx) of the sha in
  #             list serves as an identifier for the sha in map and filters.
  #   map       A list of L* packed idx pairs mapping a document to its graph
  #             head.
  #   [value]   A list of L* packed idx that match the key-value pair. These
  #             lists act as filters in searches.
  #
  # The packing format for each of the index files was chosen for performance;
  # both to minimize the footprint of the file and optimize the usage of the
  # file data.
  #--
  # Index also maintains a cache of temporary files that auto-expire after a
  # certain period of time.  The temporary files contain H* packed shas and
  # represent the results of various queries, such as rev-lists.
  #++
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
  # integers, as is the map.  The final step resolves the integers to shas,
  # but this too is simply an array lookup.  The select method encapsulates
  # this logic:
  #
  #   shas = index.select(
  #     :all => {'type' => 'comment', 'tag' => 'important'},
  #     :map => true,
  #     :shas => true
  #   )
  #
  # Importantly, any of the index files can contain duplication without
  # affecting the results of select; this allows new documents to be quickly
  # added into a filter or appended to list/map. As needed or convenient, the
  # index can compact itself and remove duplication.
  #
  class Index
    
    # A file containing the ref at which the last index was performed; used to
    # determine when a reindex is required relative to some other ref.
    HEAD = 'head'
    
    # An idx file mapping shas to their graph heads
    MAP = 'map'
    
    # A sha file listing indexed shas; the index of the sha is used as an
    # identifer for the sha in all idx files.
    LIST = 'list'
    
    # The filter directory
    FILTER = 'filter'
    
    # The head file for self
    attr_reader :head_file
    
    # The map file for self
    attr_reader :map_file
    
    # The list file for self
    attr_reader :list_file
    
    # Returns an in-memory, self-filling cache of idx files
    attr_reader :cache
    
    def initialize(path)
      @path = path
      @head_file = File.expand_path(HEAD, path)
      @map_file = File.expand_path(MAP, path)
      @list_file = File.expand_path(LIST, path)
      
      @cache = Hash.new do |key_hash, key|
        key_hash[key] = Hash.new do |value_hash, value|
          value_hash[value] = begin
            index = self.path(FILTER, key, value)
            File.exists?(index) ? IdxFile.read(index) : []
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
        entries = File.exists?(map_file) ? IdxFile.read(map_file) : []
        Hash[*entries]
      end
    end
    
    # Returns the contents of list_file, as an array.
    def list
      @list ||= (File.exists?(list_file) ? ShaFile.read(list_file) : [])
    end
    
    # Returns the segments joined to the path used to initialize self.
    def path(*segments)
      File.join(@path, *segments)
    end
    
    # Returns cache[key], a self-filling hash of filter values.  Be careful
    # not to modify index[k][v] as it is the actual cache storage.
    def [](key)
      cache[key]
    end
    
    # Returns the idx for sha, as specified in list.  If the sha is not in
    # list then it is appended to list.
    def idx(sha)
      case
      when list[-1] == sha
        list.length - 1
      when idx = list.index(sha)
        idx
      else
        idx = list.length
        list << sha
        idx
      end
    end
    
    # Return the graph head idx for the specified idx.
    def graph_head_idx(idx)
      deconvolute(idx, map)
    end
    
    def create(source)
      source_idx = idx(source)

      head_idx = graph_head_idx(source_idx)
      unless head_idx.nil? || head_idx == source_idx
        raise "create graph fail: #{source} (already associated with graph #{list[head_idx]})"
      end

      map[source_idx] = source_idx
      self
    end
    
    def link(source, target)
      associate :link, source, target
    end
    
    def update(source, target)
      associate :update, source, target
    end
    
    def delete(source)
      source_idx = idx(source)
      cache['filter']['tail'] << source_idx
      self
    end
    
    # Returns a list of possible index keys.
    def keys
      keys = cache.keys
      
      Dir.glob(self.path(FILTER, '*')).select do |path|
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
      
      base  = path(FILTER, key)
      start = base.length + 1
      Dir.glob("#{base}/**/*").each do |value_path|
        values << value_path[start, value_path.length-start]
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
    
    def select(options={})
      basis = options[:basis] || (0..list.length).to_a
      
      if all = options[:all]
        each_pair(all) do |key, value|
          basis = basis & cache[key][value]
          break if basis.empty?
        end
      end
      
      if any = options[:any]
        matches = []
        each_pair(any) do |key, value|
          matches.concat cache[key][value]
        end
        basis = basis & matches
      end
      
      if options[:map]
        basis.collect! {|idx| map[idx] }
      end
      
      if options[:shas]
        basis.collect! {|idx| list[idx] }
      end
      
      basis.uniq!
      basis
    end
    
    def compact
      # reindex shas in list, and create an idx map for updating idxs
      old_list = {}
      list.each {|sha| old_list[old_list.length] = sha }
      
      list.uniq!
      
      new_list = {}
      list.each {|sha| new_list[sha] = new_list.length}
      
      idx_map = {}
      old_list.each_pair {|idx, sha| idx_map[idx] = new_list[sha]}
      
      # update/deconvolute mapped idx values
      new_map = {}
      map.each_pair {|idx, head_idx| new_map[idx_map[idx]] = idx_map[head_idx] }
      new_map.keys.each {|idx| new_map[idx] = deconvolute(idx, new_map) || idx }
      
      @map = new_map
      
      # update filter values
      @cache.values.each do |value_hash|
        value_hash.values.each do |idxs|
          idxs.collect! {|idx| idx_map[idx] }.uniq!
        end
      end
      
      self
    end
    
    # Writes cached changes.
    def write(sha=nil)
      @cache.each_pair do |key, value_hash|
        value_hash.each_pair do |value, idx|
          IdxFile.write(path(FILTER, key, value), idx)
        end
      end
      
      FileUtils.mkdir_p(path) unless File.exists?(path)
      File.open(head_file, "w") {|io| io.write(sha) } if sha
      ShaFile.write(list_file, list.join)
      IdxFile.write(map_file, map.to_a.flatten)
      
      self
    end
    
    # Clears the cache.
    def reset
      @list = nil
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
    
    # walks up the map to find the graph head for idx.  returns nil if idx is not
    # associated with a graph
    def deconvolute(idx, map, visited=nil) # :nodoc:
      head_idx = map[idx]
      
      if visited.nil?
        if head_idx.nil?
          return nil
        else
          visited = []
        end
      end
      
      circular = visited.include?(idx)
      visited << idx
      
      if circular
        raise "cannot deconvolute cyclic graph: #{visited.inspect}"
      end
      
      head_idx == idx ? idx : deconvolute(head_idx, map, visited)
    end
    
    def associate(type, source, target) # :nodoc:
      if source == target
        raise "#{type} fail: #{source} -> #{target} (cannot #{type} with self)"
      end
      
      source_idx = idx(source)
      target_idx = idx(target)

      source_head_idx = graph_head_idx(source_idx)
      if source_head_idx.nil?
        raise "#{type} fail: #{source} -> #{target} (source is not associated with a graph)"
      end

      target_head_idx = graph_head_idx(target_idx)
      unless target_head_idx.nil? || target_head_idx == source_head_idx
        raise "#{type} fail: #{source} -> #{target} (different graph heads #{list[source_head_idx]}/#{list[target_head_idx]})"
      end
      
      map[target_idx] = source_head_idx
      cache['filter']['tail'] << source_idx

      self
    end
    
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
  end
end