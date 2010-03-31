require 'grit/actor'
require 'shellwords'

module Gitgo
  class Repo
    
    # A set of utility functions split out for ease of testing.
    module Utils
      module_function
      
      # Creates a nested sha path like: ab/xyz/paths
      def sha_path(sha, *paths)
        paths.unshift sha[2,38]
        paths.unshift sha[0,2]
        paths
      end
      
      # Creates a date/sha path like: YYYY/MMDD/sha
      def date_path(date, sha)
        date.utc.strftime("%Y/%m%d/#{sha}")
      end
      
      def state_str(state)
        case state
        when :add then '+'
        when :rm  then '-'
        else '~'
        end
      end
      
      def doc_status(sha, attrs)
        type = attrs['type']
        origin = attrs['re']
        
        [type || 'doc', origin ? "#{yield(sha)} re  #{yield(origin)}" : yield(sha)]
      end
      
      def link_status(parent, child, ref)
        case
        when parent == child
          nil
        when parent == ref
          ['update', "#{yield(child)} was #{yield(parent)}"]
        else
          ['link', "#{yield(parent)} to  #{yield(child)}"]
        end 
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