module Gitgo
  class Repo
    
    # Tree represents an in-memory working tree for git. Trees are initialized
    # with a Grit::Tree.  In general tree contents are represented as (path,
    # [:mode,sha]) pairs, but subtrees can be expanded into (path, Tree)
    # pairs.
    #
    # See Repo for an example of Tree usage in practice.
    #
    # === Efficiency
    #
    # Modes are symbolized in the internal [:mode,sha] entries because they
    # are rarely needed as strings and are typically very redundant. 
    # Symbolizing shas makes less sense because they are frequently used as
    # strings. However it does make sense to use the same string instance to
    # represent a sha in multiple places.  As a result trees have an internal
    # string_table that functions like a symbol table, ie it maps the same
    # string content to a single shared instance.  The string table is managed
    # at the class level through the string_table method.
    #
    # Trees only expand as needed.  This saves memory and cycles because it is
    # expensive to read, parse, and maintain the git tree data.  In general
    # trees will stay fairly compact unless certain expensive operations are
    # performed.  These are:
    #
    # * each_pair (with expand == true)
    # * each_tree (with expand == true)
    # * flatten
    # * to_hash   (with expand == true)
    #
    # Avoid these methods if possible, or ensure they are rarely executed.
    class Tree
      class << self
        
        # Returns the string table for shas.  Specifiy reinitialize to clear
        # and reset the string table.
        def string_table(reinitialize=false)
          @string_table = nil if reinitialize
          @string_table ||= Hash.new {|hash, key| hash[key] = key.freeze }
        end
      end
      
      # The tree mode.
      attr_reader :mode
      
      # Initializes a new Tree.  The input tree should be a Grit::Tree or nil.
      def initialize(tree=nil)
        @index = nil
        @tree = tree
        
        if tree
          self.mode = tree.mode
          self.sha  = tree.id
        else
          @mode = nil
          @sha = nil
        end
      end
      
      # Sets mode, symbolizing if necessary.  Mode may be set to nil in which
      # case the Repo::DEFAULT_TREE_MODE is adopted when a repo is commited.
      def mode=(mode)
        @mode = mode ? mode.to_sym : nil
      end
      
      # Sets the sha for self.  Sha may be set to nil, in which case it will
      # be calculated when a repo is committed.
      def sha=(sha)
        @sha = sha ? string(sha) : nil
      end
      
      # Returns the sha representing the contents for self.  If check is true,
      # sha will check that neither self nor any subtree is modified before
      # returning the sha.  If modified, the sha is set to nil to flag a repo
      # to recalculate the sha on commit.
      #
      # Note that check does not validate the sha correctly represents the
      # contents of self.
      def sha(check=true)
        if @sha && check
          index.each_value do |value|
            if value.kind_of?(Tree) && value.sha.nil?
              @sha = nil
              break
            end
          end
        end
      
        @sha
      end
      
      # Returns the keys (ie paths) for all entries in self.  Keys are
      # returned as strings
      def keys
        index.keys.collect {|keys| keys.to_s }
      end
      
      # Returns the entry for the specified path, either a [:mode,sha] pair
      # for a blob or a Tree for a subtree.
      def [](path)
        case
        when entry = index[path]
          entry
        when tree = index.delete(path.to_sym)
          index[string(path)] = Tree.new(tree)
        else
          nil
        end
      end
      
      # Sets the entry for the specified path.  The entry should be a
      # [:mode,sha] array, or a Tree.  A nil entry indicates removal.
      def []=(path, entry)
        # ensure an unexpanded tree is removed
        index.delete(path.to_sym)
        
        path = string(path)
        case entry
        when Array
          mode, sha = entry
          index[path] = [mode.to_sym, string(sha)]
        when Tree
          index[path] = entry
        when nil
          index.delete(path)
        else
          raise "invalid entry: #{entry.inspect}"
        end
        
        # add/remove content modifies self so
        # the sha can and should be invalidated
        @sha = nil
      end
      
      # Yields each (path, entry) pair to the block, ordered by path.  Entries
      # can be [:mode,sha] arrays or Trees.  If expand is true then subtrees
      # will be expanded, but strongly consider whether or not expansion is
      # necessary because it is computationally expensive.
      def each_pair(expand=false)
        
        # sorting the keys is important when writing the tree;
        # unsorted keys cause warnings in git fsck
        keys = index.keys.sort_by {|key| key.to_s }
        store = expand ? self : index
        
        keys.each {|key| yield(key, store[key]) }
      end
      
      # Yields the (path, [:mode, sha]) pairs for each blob to the block.
      def each_blob
        each_pair do |key, value|
          next unless value.kind_of?(Array)
          yield(key, value)
        end
      end
      
      # Yields the (path, entry) pairs for each tree to the block.  Subtrees
      # are expanded if specified, in which case all entries will be Trees.
      # Without expansion, entries may be [:mode,sha] arrays or Trees.
      def each_tree(expand=false)
        each_pair(expand) do |key, value|
          next unless value.kind_of?(Tree)
          yield(key, value)
        end
      end
      
      # Returns the subtree indicated by the specified segments (an array of
      # paths), or nil if no such subtree exists.  If force is true then
      # missing subtrees will be created.
      def subtree(segments, force=false)
        return self if segments.empty?
        
        key = segments.shift
        tree = self[key]

        if !tree.kind_of?(Tree)
          return nil unless force
          self[key] = tree = Tree.new(nil)
        end
        
        tree.subtree(segments, force)
      end
      
      # Flattens all paths under self into a single array.
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
      
      # Returns self as a hash, expanding if specified.
      def to_hash(expand=false)
        hash = {}
        each_pair(expand) do |key, value|
          hash[key] = case value
          when Tree  then value.to_hash
          when Array then value
          else to_entry(value)
          end
        end
        hash
      end
      
      # Returns true if the to_hash results of self and another are equal.
      def eql?(another)
        self.to_hash == another.to_hash
      end
      
      # Returns true if the to_hash results of self and another are equal.
      def ==(another)
        self.to_hash == another.to_hash
      end
      
      protected
      
      # returns or initializes the internal working tree (index)
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
      
      # helper to lookup the string table entry for key
      def string(key) # :nodoc:
        Tree.string_table[key.to_s]
      end
      
      # converts obj into a [:mode, sha] entry
      def to_entry(obj) # :nodoc:
        [obj.mode.to_sym, string(obj.id)]
      end
    end
  end
end