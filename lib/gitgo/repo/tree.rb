module Gitgo
  class Repo
    class Tree
      attr_reader :mode
      attr_reader :string_table
      
      def initialize(tree=nil, string_table=nil)
        @tree = tree
        @mode = tree ? tree.mode : nil
        @index = nil
        @string_table = string_table || Hash.new {|hash, key| hash[key] = key.freeze }
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
      end
      
      def each_pair
        keys.each do |key|
          yield(key, self[key])
        end
      end
      
      def each_blob
        each_pair do |key, value|
          next if value.kind_of?(Repo::Tree)
          yield(key, value)
        end
      end
      
      def each_tree
        each_pair do |key, value|
          next unless value.kind_of?(Repo::Tree)
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
          else to_value(value)
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
      
      def index
        @index ||= begin
          index = {}
          
          @tree.contents.each do |obj|
            key = obj.name
            if obj.respond_to?(:contents)
              index[key.to_sym] = obj
            else
              index[string(key)] = to_value(obj)
            end
          end if @tree
          @tree = nil
          
          index
        end
      end
      
      protected
      
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
      def to_value(obj) # :nodoc:
        [obj.mode.to_sym, string(obj.id)]
      end
    end
  end
end