module Gitgo
  class Repo
    
    # A variety of utility methods separated into a module to simplify
    # testing. These methods are included into and used internally by Repo.
    module Utils
      module_function
      
      def with_env(env={})
        overrides = {}
        begin
          ENV.keys.each do |key|
            if key =~ /^GIT_/
              overrides[key] = ENV.delete(key)
            end
          end

          env.each_pair do |key, value|
            overrides[key] ||= nil
            ENV[key] = value
          end

          yield
        ensure
          overrides.each_pair do |key, value|
            if value
              ENV[key] = value
            else
              ENV.delete(key)
            end
          end
        end
      end
      
      def path_segments(path)
        segments = path.kind_of?(String) ? path.split("/") : path.dup
        segments.shift if segments[0] && segments[0].empty?
        segments.pop   if segments[-1] && segments[-1].empty?
        segments
      end
      
      def flatten(ancestry)
        ancestry.each_pair do |parent, children|
          children.collect! {|child| ancestry[child] }
          children.unshift(parent)
        end
        ancestry
      end

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
  end
end