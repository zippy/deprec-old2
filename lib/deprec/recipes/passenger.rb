# Copyright 2006-2008 by Mike Bailey. All rights reserved.
Capistrano::Configuration.instance(:must_exist).load do 
  namespace :deprec do 
    namespace :passenger do
          
      set(:passenger_install_dir) { 
        if passenger_use_ree
          "#{ree_install_dir}/lib/ruby/gems/1.8/gems/passenger-2.0.6"
        else
          '/opt/passenger'
        end
      }
      
      set(:passenger_document_root) { "#{current_path}/public" }
      set :passenger_rails_allow_mod_rewrite, 'off'
      set :passenger_vhost_dir, '/etc/apache2/sites-available'
      # Default settings for Passenger config files
      set :passenger_log_level, 0
      set :passenger_user_switching, 'on'
      set :passenger_default_user, 'nobody'
      set :passenger_max_pool_size, 6
      set :passenger_max_instances_per_app, 0
      set :passenger_pool_idle_time, 300
      set :passenger_rails_autodetect, 'on'
      set :passenger_rails_spawn_method, 'smart' # smart | conservative
      set :use_mod_rewrite_for_disable, false

      SRC_PACKAGES[:passenger] = {
        :url => "git://github.com/FooBarWidget/passenger.git",
        :download_method => :git,
        :version => 'release-2.0.6', # Specify a tagged release to deploy
        :configure => '',
        :make => '',
        :install => './bin/passenger-install-apache2-module'
      }

      desc "Install passenger"
      task :install, :roles => :app do
        install_deps
        deprec2.download_src(SRC_PACKAGES[:passenger], src_dir)

        if passenger_use_ree
          # Install the Passenger that came with Ruby Enterprise Edition
          run "yes | #{sudo} env PATH=#{ree_install_dir}/bin:$PATH #{ree_install_dir}/bin/passenger-install-apache2-module"
        else
          # Non standard - passenger requires input
          package_dir = File.join(src_dir, 'passenger.git')
          dest_dir = passenger_install_dir + '-' + (SRC_PACKAGES[:passenger][:version] || 'trunk')
          run "#{sudo} rsync -avz #{package_dir}/ #{dest_dir}"
          run "cd #{dest_dir} && yes '' | #{sudo} ./bin/passenger-install-apache2-module"
          run "#{sudo} unlink #{passenger_install_dir} 2>/dev/null; #{sudo} ln -sf #{dest_dir} #{passenger_install_dir}"
        end
        
        initial_config_push
        
      end
      
      task :initial_config_push, :roles => :web do
        # XXX Non-standard!
        # We need to push out the .load and .conf files for Passenger
        SYSTEM_CONFIG_FILES[:passenger].each do |file|
          deprec2.render_template(:passenger, file.merge(:remote => true))
        end
      end

      # Install dependencies for Passenger
      task :install_deps, :roles => :app do
        apt.install( {:base => %w(apache2-mpm-prefork apache2-prefork-dev rsync)}, :stable )
        gem2.install 'fastthread'
        gem2.install 'rack'
        gem2.install 'rake'
        # These are more Rails than Passenger - Mike
        # gem2.install 'rails'
        # gem2.install "mysql -- --with-mysql-config='/usr/bin/mysql_config'"
        # gem2.install 'sqlite3-ruby'
        # gem2.install 'postgres'
      end
      
      SYSTEM_CONFIG_FILES[:passenger] = [

        {:template => 'passenger.load.erb',
          :path => '/etc/apache2/mods-available/passenger.load',
          :mode => 0755,
          :owner => 'root:root'},
          
        {:template => 'passenger.conf.erb',
          :path => '/etc/apache2/mods-available/passenger.conf',
          :mode => 0755,
          :owner => 'root:root'}

      ]

      PROJECT_CONFIG_FILES[:passenger] = [

        { :template => 'apache_vhost.erb',
          :path => "apache_vhost",
          :mode => 0755,
          :owner => 'root:root'},

        { :template => 'apache_vhost_disabled.erb',
          :path => 'apache_vhost_disabled',
          :mode => 0755,
          :owner => 'root:root'}

      ]
       
      desc "Generate Passenger apache configs (system & project level)."
      task :config_gen do
        config_gen_system 
        config_gen_project
      end

      desc "Generate Passenger apache configs (system level) from template."
      task :config_gen_system do
        SYSTEM_CONFIG_FILES[:passenger].each do |file|
          deprec2.render_template(:passenger, file)
        end
      end

      desc "Generate Passenger apache configs (project level) from template."
      task :config_gen_project do
        PROJECT_CONFIG_FILES[:passenger].each do |file|
          deprec2.render_template(:passenger, file)
        end
      end

      desc "Push Passenger config files (system & project level) to server"
      task :config, :roles => :app do
        config_system
        config_project  
      end

      desc "Push Passenger configs (system level) to server"
      task :config_system, :roles => :app do
        deprec2.push_configs(:passenger, SYSTEM_CONFIG_FILES[:passenger])
        activate_system
      end

      desc "Push Passenger configs (project level) to server"
      task :config_project, :roles => :app do
        deprec2.push_configs(:passenger, PROJECT_CONFIG_FILES[:passenger])
        symlink_passenger_vhost
        activate_project
      end

      task :symlink_passenger_vhost, :roles => :app do
        sudo "ln -sf #{deploy_to}/passenger/apache_vhost #{passenger_vhost_dir}/#{application}"
        sudo "ln -sf #{deploy_to}/passenger/apache_vhost_disabled #{passenger_vhost_dir}/#{application}_disabled"
      end
      
      task :activate, :roles => :app do
        activate_system
        activate_project
      end
      
      task :activate_system, :roles => :app do
        sudo "a2enmod passenger"
        if use_mod_rewrite_for_disable
          sudo "a2enmod rewrite"
        end
        top.deprec.web.reload
      end
      
      task :activate_project, :roles => :app do
        sudo "a2ensite #{application}"
        top.deprec.web.reload
      end
      
      task :deactivate do
        puts
        puts "******************************************************************"
        puts
        puts "Danger!"
        puts
        puts "Do you want to deactivate just this project or all Passenger"
        puts "projects on this server? Try a more granular command:"
        puts
        puts "cap deprec:passenger:deactivate_system  # disable Passenger"
        puts "cap deprec:passenger:deactivate_project # disable only this project"
        puts
        puts "******************************************************************"
        puts
      end
      
      task :deactivate_system, :roles => :app do
        sudo "a2dismod passenger"
        top.deprec.web.reload
      end
      
      task :deactivate_project, :roles => :app do
        sudo "a2dissite #{application}"
        top.deprec.web.reload
      end
      
      desc <<-DESC
        Present a maintenance page to visitors. Disables your application's web \
        interface by writing a "maintenance.html" file to each web server. 

        By default, the maintenance page will just say the site is down for \
        "maintenance", and will be back "shortly", but you can customize the \
        page by specifying the REASON and UNTIL environment variables:

          $ cap deprec:passenger:disable \\
                REASON="hardware upgrade" \\
                UNTIL="12pm Central Time"

        You can customize this page by putting what ever html you want in a \
        config/templates/passgenger/mantenance.html.erb file
      DESC
      task :disable_app do
        on_rollback { run "rm #{shared_path}/system/maintenance.html" }
        deprec2.render_template(:passenger,
          :template => 'maintenance.html.erb',
          :path => "#{shared_path}/system/maintenance.html",
          :mode => 0755,
          :owner => 'root:root',
          :remote => true)
        unless use_mod_rewrite_for_disable
          sudo "a2dissite #{application}"
          sudo "a2ensite #{application}_disabled"
          top.deprec.web.reload
        end
      end
      
      desc <<-DESC
        Makes the application web-accessible again. Removes the \
        "maintenance.html" page generated by deploy:web:disable, which (if your \
        web servers are configured correctly) will make your application \
        web-accessible again.
      DESC
      task :enable_app do
        run "rm #{shared_path}/system/maintenance.html"
        unless use_mod_rewrite_for_disable
          sudo "a2ensite #{application}"
          sudo "a2dissite #{application}_disabled"
          top.deprec.web.reload
        end
      end

      desc "Restart Application"
      task :restart, :roles => :app do
        run "touch #{current_path}/tmp/restart.txt"
      end
      
      desc "Restart Apache"
      task :restart_apache, :roles => :passenger do
        run "#{sudo} /etc/init.d/apache2 restart"
      end
      
    end
    
    namespace :ree do
      
      set :ree_version, 'ruby-enterprise-1.8.6-20090113'
      set :ree_install_dir, "/opt/#{ree_version}"
      set :ree_short_path, '/opt/ruby-enterprise'
      
      SRC_PACKAGES[:ree] = {
        :md5sum => "e8d796a5bae0ec1029a88ba95c5d901d #{ree_version}.tar.gz",
        :url => "http://rubyforge.org/frs/download.php/50087/#{ree_version}.tar.gz",
        :configure => '',
        :make => '',
        :install => "./installer --auto /opt/#{ree_version}"
      }
 
      task :install do
        install_deps
        deprec2.download_src(SRC_PACKAGES[:ree], src_dir)
        deprec2.install_from_src(SRC_PACKAGES[:ree], src_dir)
        symlink_ree
      end
      
      task :install_deps do
        apt.install({:base => %w(libssl-dev libmysqlclient15-dev libreadline5-dev)}, :stable)
      end
      
      task :symlink_ree do
        sudo "ln -sf /opt/#{ree_version} #{ree_short_path}"
        sudo "ln -fs #{ree_short_path}/bin/gem /usr/local/bin/gem"
        sudo "ln -fs #{ree_short_path}/bin/irb /usr/local/bin/irb"
        sudo "ln -fs #{ree_short_path}/bin/rake /usr/local/bin/rake"
        sudo "ln -fs #{ree_short_path}/bin/rails /usr/local/bin/rails"
        sudo "ln -fs #{ree_short_path}/bin/ruby /usr/local/bin/ruby"
      end
      
    end
    
  end
end