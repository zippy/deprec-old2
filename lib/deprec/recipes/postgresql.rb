# Copyright 2006-2008 by Saulius Grigaitis. All rights reserved.
# Backported from centostrano to deprec by Eric Harris-Braun.
Capistrano::Configuration.instance(:must_exist).load do 
  namespace :deprec do
    namespace :postgresql do
      
      # Installation
      desc "Install postgresql"
      task :install, :roles => :db do
        install_deps
        #that's hack to initialize database (this should be replaced with initdb or so)
#        start
#        config_gen
#        config
#        restart
      end
      
      # Install dependencies for PostgreSQL 
      task :install_deps, :roles => :db do
        apt.install( {:base => %w(postgresql postgresql-client libpq-dev)}, :stable )  #for ubuntu 8.04 
#        apt.install( {:base => %w(postgresql)}, :stable )  #for ubuntu 8.10
      end
 
      desc "Create Database" 
      task :create_db, :roles => :db do
        read_config
#        createuser(db_user, db_password)
        createdb(db_name, db_user)
      end
      
      desc "Create DB according to production settings in database.yml"
      task :setup_db do
        top.deprec.postgresql.activate
        top.deprec.postgresql.start
        top.deprec.postgresql.create_db
      end
 
      
      # Configuration
      
      SYSTEM_CONFIG_FILES[:postgresql] = [
        
        {:template => "pg_hba.conf.erb",
         :path => '/var/lib/pgsql/data/pg_hba.conf',
         :mode => 0644,
         :owner => 'root:root'}
      ]
      
      desc "Generate configuration file(s) for postgresql from template(s)"
      task :config_gen do
        SYSTEM_CONFIG_FILES[:postgresql].each do |file|
          deprec2.render_template(:postgresql, file)
        end
      end
      
      desc "Push postgresql config files to server"
      task :config, :roles => :db do
        deprec2.push_configs(:postgresql, SYSTEM_CONFIG_FILES[:postgresql])
      end
      
      task :activate, :roles => :db do
        send(run_method, "update-rc.d postgresql-8.3 defaults")
      end  
      
      task :deactivate, :roles => :db do
        send(run_method, "update-rc.d -f postgresql-8.3 remove")
      end
      
      # Control
      
      desc "Start PostgreSQL"
      task :start, :roles => :db do
        send(run_method, "/etc/init.d/postgresql-8.3 start")
      end
      
      desc "Stop PostgreSQL"
      task :stop, :roles => :db do
        send(run_method, "/etc/init.d/postgresql-8.3 stop")
      end
      
      desc "Restart PostgreSQL"
      task :restart, :roles => :db do
        send(run_method, "/etc/init.d/postgresql-8.3 restart")
      end
      
      desc "Reload PostgreSQL"
      task :reload, :roles => :db do
        send(run_method, "/etc/init.d/postgresql-8.3 reload")
      end
      
      task :backup, :roles => :db do
      end
      
      task :restore, :roles => :db do
      end
            
    end
  end
 
# Imported from Rails Machine gem (Copyright (c) 2006 Bradley Taylor, bradley@railsmachine.com)
 
  def createdb(db, user)
    sudo "su - postgres -c \'createdb -O #{user} #{db}\'"  
  end
  
  def createuser(user, password)
    cmd = "su - postgres -c \'createuser -P -D -A -E #{user}\'"
    sudo cmd do |channel, stream, data|
      if data =~ /^Enter password for new/
        channel.send_data "#{password}\n" 
      end
      if data =~ /^Enter it again:/
        channel.send_data "#{password}\n" 
      end
      if data =~ /^Shall the new role be allowed to create more new roles?/
        channel.send_data "n\n" 
      end
    end
  end
  
  def command(sql, database)
    run "psql --command=\"#{sql}\" #{database}" 
  end
  
  def read_config
    db_config = YAML.load_file('config/database.yml')
    set :db_user, db_config[rails_env]["username"]
    set :db_password, db_config[rails_env]["password"] 
    set :db_name, db_config[rails_env]["database"]
  end
end