module Gitgo
  class Repo
    class Tree
      attr_reader :mode
      attr_reader :string_table
      
      def initialize(tree=nil, string_table=nil)
        @string_table = string_table || Hash.new {|hash, key| hash[key] = key.freeze }
        @index = nil
        @mode = nil
        @sha = nil
        
        @tree = tree
        if tree
          self.mode = tree.mode
          self.sha  = tree.id
        end
      end
      
      def mode=(mode)
        @mode = mode ? mode.to_sym : nil
      end
      
      def sha=(sha)
        @sha = sha ? string(sha) : nil
      end
      
      def sha(validate=true)
        if @sha && validate
          index.each_value do |value|
            if value.kind_of?(Tree) && value.sha.nil?
              @sha = nil
              break
            end
          end
        end
      
        @sha
      end
      
      def keys
        index.keys.collect {|key| key.to_s }
      end

      def [](key)
        case
        when entry = index[key]
          entry
        when tree = index.delete(key.to_sym)
          index[string(key)] = Tree.new(tree, string_table)
        else
          nil
        end
      end

      def []=(key, content)
        index.delete(key.to_sym)
        
        if content.nil?
          index.delete(key)
        else
          index[string(key)] = content
        end
        
        # mark modified if any content is added/removed
        @sha = nil
      end
      
      # To maintain performance it is imperative that trees only be expanded
      # as needed.  To promote this practice the default for each_pair is to
      # not expand the entries.  Strongly consider whether or not you need
      # expansion before setting expand to true.
      def each_pair(expand=false)
        if expand
          keys.each do |key|
            yield(key, self[key])
          end
        else
          index.each_pair do |key, value|
            yield(key, value)
          end
        end
      end
      
      def each_blob
        each_pair do |key, value|
          next if value.kind_of?(Tree)
          yield(key, value)
        end
      end
      
      def each_tree(expand=false)
        each_pair(expand) do |key, value|
          next unless value.kind_of?(Tree)
          yield(key, value)
        end
      end
      
      def subtree(segments, force=false)
        return self if segments.empty?
        
        key = segments.shift
        tree = self[key]

        if !tree.kind_of?(Tree)
          return nil unless force
          self[key] = tree = Tree.new(nil, string_table)
        end
        
        tree.subtree(segments, force)
      end
      
      def flatten(prefix=nil, target={})
        keys.each do |key|
          next unless entry = self[key]

          key = key.to_s
          key = File.join(prefix, key) if prefix

          if entry.kind_of?(Tree)
            entry.flatten(key, target)
          else
            target[key] = entry
          end
        end

        target
      end
      
      def to_hash
        hash = {}
        index.each_pair do |key, value|
          hash[key] = case value
          when Tree  then value.to_hash
          when Array then value
          else to_entry(value)
          end
        end
        hash
      end
      
      def ==(another)
        self.to_hash == another.to_hash
      end
      
      def inspect
        to_hash.inspect
      end
      
      protected
      
      def index # :nodoc:
        @index ||= begin
          index = {}
          
          @tree.contents.each do |obj|
            key = obj.name
            if obj.respond_to?(:contents)
              index[key.to_sym] = obj
            else
              index[string(key)] = to_entry(obj)
            end
          end if @tree
          @tree = nil
          
          index
        end
      end
      
      # all keys for index may (and should) be mapped for space saving
      def string(key) # :nodoc:
        string_table[key.to_s]
      end
      
      # === Rationale
      #
      # Modes never really get used as strings and are highly redundant so
      # symbolizing them makes sense.  Symbolizing the sha makes much less
      # sense (in many places the sha must be as string) but it does make
      # sense to use the same string to cut down on memory usage.  Analagous
      # to a symbol table, Tree uses sha_table to map strings to a single
      # string instance where possible.
      #
      def to_entry(obj) # :nodoc:
        [obj.mode.to_sym, string(obj.id)]
      end
    end
  end
end