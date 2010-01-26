module Gitgo
  # The expanded path to the Gitgo root directory, used for resolving paths to
  # views, public files, etc.
  ROOT = File.expand_path(File.dirname(__FILE__) + "/../..")
  
  REPO = 'gitgo.repo'
  MOUNT = 'gitgo.mount'
  
  MAJOR = 0
  MINOR = 1
  TINY = 1
  
  VERSION = "#{MAJOR}.#{MINOR}.#{TINY}"
  WEBSITE = "http://github.com/pinnacol/gitgo"
end