require 'grit/actor'
require 'shellwords'

module Gitgo
  class Repo
    
    # A set of utility functions split out for ease of testing.
    module Utils
      module_function

      # Returns the sha for an empty string, and ensures the corresponding
      # object is set in the repo.
      def empty_sha # :nodoc:
        @empty_sha ||= begin
          empty_sha = git.set(:blob, "")
          git['gitgo'] = ['100644'.to_sym, empty_sha]
          empty_sha
        end
      end
      
      # Creates a nested sha path like: ab/xyz/paths
      def sha_path(sha, *paths)
        paths.unshift sha[2,38]
        paths.unshift sha[0,2]
        paths
      end
      
      def state_str(state)
        case state
        when :add then '+'
        when :rm  then '-'
        else '~'
        end
      end
      
      def create_status(sha, attrs)
        type = attrs['type']
        [type || 'doc', yield(sha)]
      end
      
      def link_status(parent, child)
        ['link', "#{yield(parent)} to  #{yield(child)}"]
      end
      
      def update_status(old_sha, new_sha)
        ['update', "#{yield(new_sha)} was #{yield(old_sha)}"]
      end
      
      def delete_status(sha)
        ['delete', yield(sha)]
      end
      
      def format_status(lines)
        indent = lines.collect {|(state, type, msg)| type.length }.max
        format = "%s %-#{indent}s %s"
        lines.collect! {|ary| format % ary }
        lines.sort!
        lines
      end
    end
  end
end