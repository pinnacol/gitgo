module Gitgo
  class Repo
    class Cache
      
      def initialize(store={})
        @store = store
      end
      
      def entries(sha)
        @store[sha] ||= {}
      end
      
      def get(sha, key)
        entries(sha)[key]
      end
      
      def set(sha, key, value)
        entries(sha)[key] = value
      end
      
      def query(sha, key)
        entries(sha)[key] ||= yield
      end
      
      def reset(*shas)
        shas.each do |sha|
          @store.delete(sha)
        end
      end
      
      def clear
        @store.clear
      end
      
      def to_hash
        @store
      end
    end
  end
end