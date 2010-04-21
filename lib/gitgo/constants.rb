require 'gitgo/version'

module Gitgo
  # The expanded path to the Gitgo root directory, used for resolving paths to
  # views, public files, etc.
  ROOT = File.expand_path(File.dirname(__FILE__) + "/../..")
  
  REPO_ENV_VAR  = 'gitgo.repo'
  MOUNT_ENV_VAR = 'gitgo.mount'
end