require 'fileutils'

module Gitgo
  class Index
    
    # ShaFile is a wrapper providing access to a file of H packed shas.
    class ShaFile
      class << self
        
        # Opens and returns an sha file in the specified mode.  If a block is
        # given the file is yielded to it and closed afterwards; in this case
        # the return of open is the block result.
        def open(path, mode="r")
          sha_file = new(File.open(path, mode))
          
          return sha_file unless block_given?

          begin
            yield(sha_file)
          ensure
            sha_file.close
          end
        end
        
        # Reads the file and returns an array of shas.
        def read(path)
          open(path) {|sha_file| sha_file.read(nil) }
        end
        
        # Opens the file and writes the sha; previous contents are replaced. 
        # Multiple shas may be written at once by providing a string of
        # concatenated shas. 
        def write(path, sha)
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir) unless File.exists?(dir)
          open(path, "w") {|sha_file| sha_file.write(sha) }
        end
        
        # Opens the file and appends the sha.  Multiple shas may be appended
        # at once by providing a string of concatenated shas.
        def append(path, sha)
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir) unless File.exists?(dir)
          open(path, "a") {|sha_file| sha_file.write(sha) }
        end
        
        # Opens the file and removes the shas.
        def rm(path, *shas)
          return unless File.exists?(path)
          
          current = read(path)
          write(path, (current-shas).join)
        end
      end
      
      # The pack format, optimized for packing multiple shas
      PACK = "H*"
      
      # The unpacking format
      UNPACK = "H40"
      
      # The size of an unpacked sha
      ENTRY_SIZE = 40
      
      # The size of a packed sha
      PACKED_ENTRY_SIZE = 20
      
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
          raise "invalid packed sha length: #{str.length}"
        end
        entries = str.unpack(UNPACK * (str.length / PACKED_ENTRY_SIZE))

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
        unless sha.length % ENTRY_SIZE == 0
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