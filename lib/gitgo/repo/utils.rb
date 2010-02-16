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
      
      def deserialize(str, sha=nil)
        attrs, content = str.split(/\n--- \n/m, 2)
        unless attrs.nil? || attrs.empty?
          attrs = YAML.load(attrs.to_s)
        end

        unless attrs.kind_of?(Hash)
          return nil
        end
        
        attrs['content'] = content
        attrs
      end
      
      # Serializes the document into an attributes section and a content
      # section, joined as a YAML document plus a string:
      #
      #   --- 
      #   author: John Doe <john.doe@email.com>
      #   date: 1252508400.123
      #   type: document
      #   --- 
      #   content...
      #
      def serialize(attrs)
        hash = {}
        attrs.each_pair do |key, value|
          hash[key] = value unless blank?(value)
        end
        content = hash.delete('content')

        hash.extend(SortedToYaml)
        "#{hash.to_yaml}--- \n#{content}"
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
      
      # Flattens an ancestry hash of (parent, [children]) pairs.  For example:
      #
      #   ancestry = {
      #     "a" => ["b"],
      #     "b" => ["c", "d"],
      #     "c" => [],
      #     "d" => ["e"],
      #     "e" => []
      #   }
      #
      #   flatten(ancestry) 
      #   # => {
      #   # "a" => ["a", ["b", ["c"], ["d", ["e"]]]],
      #   # "b" => ["b", ["c"], ["d", ["e"]]],
      #   # "c" => ["c"],
      #   # "d" => ["d", ["e"]],
      #   # "e" => ["e"]
      #   # }
      #
      # Note that the flattened ancestry re-uses the array values, such that
      # modifiying the "b" array will propagate to the "a" ancestry.
      def flatten(ancestry)
        ancestry.each_pair do |parent, children|
          next unless children
          
          children.collect! {|child| ancestry[child] }
          children.compact!
          children.unshift(parent)
        end
        ancestry
      end
      
      # Collapses an nested array hierarchy such that nesting is only
      # preserved for existing, and not just potential, branches:
      #
      #   collapse(["a", ["b", ["c"]]])               # => ["a", "b", "c"]
      #   collapse(["a", ["b", ["c"], ["d", ["e"]]]]) # => ["a", "b", ["c"], ["d", "e"]]
      #
      def collapse(array, result=[])
        result << array.at(0)

        if (length = array.length) == 2
          collapse(array.at(1), result)
        else
          1.upto(length-1) do |i|
            result << collapse(array.at(i))
          end
        end

        result
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