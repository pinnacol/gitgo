require 'fileutils'

module Gitgo
  class Index
    
    # IdxFile is a wrapper providing access to a file of L packed integers.
    class IdxFile
      class << self
        
        # Opens and returns an idx file in the specified mode.  If a block is
        # given the file is yielded to it and closed afterwards; in this case
        # the return of open is the block result.
        def open(path, mode="r")
          idx_file = new(File.open(path, mode))
          
          return idx_file unless block_given?

          begin
            yield(idx_file)
          ensure
            idx_file.close
          end
        end
        
        # Reads the file and returns an array of integers.
        def read(path)
          open(path) {|idx_file| idx_file.read(nil) }
        end
        
        # Opens the file and writes the integer; previous contents are
        # replaced.  Provide an array of integers to write multiple integers
        # at once.
        def write(path, int)
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir) unless File.exists?(dir)
          open(path, "w") {|idx_file| idx_file.write(int) }
        end
        
        # Opens the file and appends the int. Provide an array of integers to
        # append multiple integers at once.
        def append(path, int)
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir) unless File.exists?(dir)
          open(path, "a") {|idx_file| idx_file.write(int) }
        end
        
        # Opens the file and removes the integers.
        def rm(path, *ints)
          return unless File.exists?(path)
          
          current = read(path)
          write(path, (current-ints))
        end
      end
      
      # The pack format
      PACK = "L*"
      
      # The unpack format
      UNPACK = "L*"
      
      # The size of a packed integer
      PACKED_ENTRY_SIZE = 4
      
      # The file being wrapped
      attr_reader :file
      
      # Initializes a new ShaFile with the specified file.  The file will be
      # set to binary mode.
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
        file.pos / PACKED_ENTRY_SIZE
      end
      
      # Reads n entries from the start index and returns them as an array. Nil
      # n will read all remaining entries and nil start will read from the
      # current index.
      def read(n=10, start=0)
        if start
          start_pos = start * PACKED_ENTRY_SIZE 
          file.pos = start_pos
        end
        
        str = file.read(n.nil? ? nil : n * PACKED_ENTRY_SIZE).to_s
        unless str.length % PACKED_ENTRY_SIZE == 0
          raise "invalid packed int length: #{str.length}"
        end
        
        str.unpack(UNPACK)
      end
      
      # Writes the integers to the file at the current index.  Provide an
      # array of integers to write multiple integers at once.
      def write(int)
        int = [int] unless int.respond_to?(:pack)
        file.write int.pack(PACK)
        self
      end
      
      # Appends the integers to the file. Provide an array of integers to
      # append multiple integers at once.
      def append(int)
        file.pos = file.size
        write(int)
        self
      end
    end
  end
end