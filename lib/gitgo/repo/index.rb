module Gitgo
  class Repo
    
    # Index is a wrapper providing access to a file of packed shas.  Such
    # files are used as indexes of, for instance, all documents with some
    # key-value attribute pair.
    class Index
      class << self
        
        # Opens and returns an index file in the specified mode.  If a block
        # is given the index is yielded to it and closed afterwards; in this
        # case the return of open is the block result.
        def open(path, mode="r")
          idx = new File.open(path, mode)
          
          return idx unless block_given?

          begin
            yield(idx)
          ensure
            idx.close
          end
        end
      end
      
      # The pack format, optimized for packing multiple shas
      PACK = "H*"
      
      # The unpacking format
      UNPACK = "H40"
      
      # The size of a packed sha
      ENTRY_SIZE = 20
      
      # The file being wrapped
      attr_reader :file
      
      # Initializes a new Index with the specified file.  The file will be set
      # to binary mode.
      def initialize(file)
        file.binmode
        @file = file
      end
      
      # Closes file
      def close
        file.close
      end
      
      # The index of the current entry.
      def current
        file.pos / ENTRY_SIZE
      end
      
      # Returns the number of entries in self.
      def length
        file.size / ENTRY_SIZE
      end
      
      # Reads n entries from the start index and returns them as an array. Nil
      # n will read all remaining entries and nil start will read from the
      # current index.
      def read(n=10, start=0)
        if start
          start_pos = start * ENTRY_SIZE 
          file.pos = start_pos
        end
        
        unless n
          n = (file.size - file.pos)/ENTRY_SIZE
        end
        
        entries = file.read(n * ENTRY_SIZE).to_s.unpack(UNPACK * n)
        
        # clear out all missing entries, which will be empty
        while last = entries.last
          if last.empty?
            entries.pop
          else
            break
          end
        end
        
        entries
      end
      
      # Writes the sha to the file at the current index.  Multiple shas may be
      # written at once by providing a string of concatenated shas.
      def write(sha)
        unless sha.length % 40 == 0
          raise "invalid sha length: #{sha.length}"
        end
        
        file.write [sha].pack(PACK)
        self
      end
      
      # Appends the sha to the file.  Multiple shas may be appended at once by
      # providing a string of concatenated shas.
      def append(sha)
        file.pos = file.size
        write(sha)
        self
      end
    end
  end
end