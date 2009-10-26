module Gitgo
  class Repo
    class Tree
      attr_reader :mode
      
      def initialize(tree=nil)
        @tree = tree
        @mode = tree ? tree.mode : nil
      end
      
      def keys
        index.keys.collect {|key| key.to_s }.sort
      end

      def [](key)
        case
        when entry = index[key]
          entry
        when tree = index.delete(key.to_sym)
          index[key.to_s] = Tree.new(tree)
        else
          nil
        end
      end

      def []=(key, content)
        index.delete(key.to_sym)
        
        if content.nil?
          index.delete(key)
        else
          index[key] = content
        end
      end
      
      def each_pair
        keys.each do |key|
          yield(key, self[key])
        end
      end
      
      def subtree(segments, force=false)
        return self if segments.empty?
        
        key = segments.shift
        tree = self[key]

        if !tree.kind_of?(Tree)
          return nil unless force
          index[key] = tree = Tree.new
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
          else [value.mode, value.id]
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
              index[key] = [obj.mode, obj.id]
            end
          end if @tree
          @tree = nil
          
          index
        end
      end
    end
  end
end