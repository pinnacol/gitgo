module Gitgo
  class Repo
    module Utils
      
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
      
    end
  end
end