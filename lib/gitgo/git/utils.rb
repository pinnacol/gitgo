module Gitgo
  class Git
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
      
      def split(path)
        array = path.kind_of?(String) ? path.split("/") : path.dup
        array.shift if nil_or_empty?(array[0])
        array.pop   if nil_or_empty?(array[-1])
        array
      end
      
      def nil_or_empty?(obj)
        obj.nil? || obj.empty?
      end
    end
  end
end