# Copyright 2006-2008 by Mike Bailey. All rights reserved.
Capistrano::Configuration.instance(:must_exist).load do 
  namespace :deprec do
    namespace :emacs do
      desc "Install Emacs"
      task :install do
        install_deps
      end

      desc "install dependencies for Emacs"
      task :install_deps do
        apt.install( {:base => %w(emacs)}, :stable )
      end
    end
  end
end