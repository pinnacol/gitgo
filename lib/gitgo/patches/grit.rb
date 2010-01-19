module Gitgo
  module Patches
    class Grit::Actor
      def <=>(another)
        name <=> another.name
      end
    end
    
    class Grit::Commit
      
      # This patch allows file add/remove to be detected in diffs.  For some
      # reason with the original version (commented out) the diff is missing
      # certain crucial lines in the output:
      #
      #   diff --git a/alpha.txt b/alpha.txt
      #   index 0000000000000000000000000000000000000000..15db91c38a4cd47235961faa407304bf47ea5d15 100644
      #   --- a/alpha.txt
      #   +++ b/alpha.txt
      #   @@ -1 +1,2 @@
      #   +Contents of file alpha.
      #  
      # vs
      #
      #   diff --git a/alpha.txt b/alpha.txt
      #   new file mode 100644
      #   index 0000000000000000000000000000000000000000..15db91c38a4cd47235961faa407304bf47ea5d15
      #   --- /dev/null
      #   +++ b/alpha.txt
      #   @@ -0,0 +1 @@
      #   +Contents of file alpha.
      #
      # Perhaps the original drops into the pure-ruby version of git?
      def self.diff(repo, a, b = nil, paths = [])
        if b.is_a?(Array)
          paths = b
          b     = nil
        end
        paths.unshift("--") unless paths.empty?
        paths.unshift(b)    unless b.nil?
        paths.unshift(a)
        # text = repo.git.diff({:full_index => true}, *paths)
        text = repo.git.run('', :diff, '', {:full_index => true}, paths)
        Grit::Diff.list_from_string(repo, text)
      end
    end
  end
end