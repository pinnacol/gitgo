require 'grit/actor'
require 'shellwords'

module Gitgo
  class Repo
    module Utils
      module_function
      
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
      
      # Creates a nested sha path like:
      #
      #   ab/
      #     xyz...
      #
      def sha_path(sha, *paths)
        paths.unshift sha[2,38]
        paths.unshift sha[0,2]
        paths
      end
      
      def date_path(date, sha)
        date.utc.strftime("%Y/%m%d/#{sha}")
      end
    end
    
    # A module to replace the Hash#to_yaml function to serialize with sorted keys.
    #
    # From: http://snippets.dzone.com/posts/show/5811
    # The original function is in: /usr/lib/ruby/1.8/yaml/rubytypes.rb
    #
    module SortedToYaml # :nodoc:
      def to_yaml( opts = {} )
        YAML::quick_emit( object_id, opts ) do |out|
          out.map( taguri, to_yaml_style ) do |map|
            sort.each do |k, v|
              map.add( k, v )
            end
          end
        end
      end
    end
  end
end