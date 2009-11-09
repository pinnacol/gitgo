module Gitgo
  class Repo
    class Index
      class << self
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
      
      PACK = "H*"
      UNPACK = "H40"
      ENTRY_SIZE = 20
      
      attr_reader :file
      
      def initialize(file)
        @file = file
      end
      
      def close
        file.close
      end
      
      def length
        file.size / ENTRY_SIZE
      end
      
      def read(n=10, start=0)
        start_pos = start * ENTRY_SIZE 
        file.pos = start_pos
        
        n ||= (file.size - start_pos)/ENTRY_SIZE
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
      
      def write(sha)
        file.pos = file.size
        file.write [sha].pack(PACK)
        self
      end
      
      def replace(*shas)
        file.pos = 0
        file.write [shas.join].pack(PACK)
        self
      end
    end
  end
end