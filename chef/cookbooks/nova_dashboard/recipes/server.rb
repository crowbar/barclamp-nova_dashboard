# Copyright 2011 Dell, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "apache2"
include_recipe "apache2::mod_wsgi"
include_recipe "apache2::mod_rewrite"

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)

dashboard_path = "/usr/share/openstack-dashboard"
venv_path = node[:nova_dashboard][:use_virtualenv] ? "#{dashboard_path}/.venv" : nil
venv_prefix = node[:nova_dashboard][:use_virtualenv] ? ". #{venv_path}/bin/activate &&" : nil

unless node[:nova_dashboard][:use_gitrepo]
  # Explicitly added client dependencies for now.
  packages = [ "openstack-dashboard", "python-novaclient", "python-glance", "python-swift", "python-keystone", "openstackx", "python-django", "python-django-horizon", "python-django-nose", "nodejs", "node-less" ]
  packages.each do |pkg|
    package pkg do
      action :install
    end
  end
  
  rm_pkgs = [ "openstack-dashboard-ubuntu-theme" ]
  rm_pkgs.each do |pkg|
    package pkg do
      action :purge
    end
  end
else
  pfs_and_install_deps "nova_dashboard" do
    path dashboard_path
    virtualenv venv_path
  end
  execute "chown_www-data" do
    command "chown -R www-data:www-data #{dashboard_path}"
  end
end


directory "#{dashboard_path}/.blackhole" do
  owner "www-data"
  group "www-data"
  mode "0755"
  action :create
end
  
directory "/var/www" do
  owner "www-data"
  group "www-data"
  mode "0755"
  action :create
end
  
apache_site "000-default" do
  enable false
end

template "#{node[:apache][:dir]}/sites-available/nova-dashboard.conf" do
  source "nova-dashboard.conf.erb"
  mode 0644
  variables(
    :horizon_dir => dashboard_path,
    :venv => node[:nova_dashboard][:use_virtualenv],
    :venv_path => venv_path
  )
  if ::File.symlink?("#{node[:apache][:dir]}/sites-enabled/nova-dashboard.conf")
    notifies :reload, resources(:service => "apache2")
  end
end

if node[:nova_dashboard][:use_virtualenv]
  template "/usr/share/openstack-dashboard/openstack_dashboard/wsgi/django_venv.wsgi" do
    source "django_venv.wsgi.erb"
    mode 0644
    variables(
      :venv_path => venv_path
    )
  end
end

file "/etc/apache2/conf.d/openstack-dashboard.conf" do
  action :delete
end

apache_site "nova-dashboard.conf" do
  enable true
end

node.set_unless['dashboard']['db']['password'] = secure_password

if node[:nova_dashboard][:sql_engine] == "mysql"
    Chef::Log.info("Configuring Horizion to use MySQL backend")
    include_recipe "mysql::client"

    package "python-mysqldb" do
        action :install
    end


    env_filter = " AND mysql_config_environment:mysql-config-#{node[:nova_dashboard][:mysql_instance]}"
    mysqls = search(:node, "recipes:mysql\\:\\:server#{env_filter}") || []
    if mysqls.length > 0
        mysql = mysqls[0]
        mysql = node if mysql.name == node.name
    else
        mysql = node
    end

    mysql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(mysql, "admin").address if mysql_address.nil?
    Chef::Log.info("Mysql server found at #{mysql_address}")

    # Create the Dashboard Database
    mysql_database "create #{node[:dashboard][:db][:database]} database" do
        host	mysql_address
        username "db_maker"
        password mysql[:mysql][:db_maker_password]
        database node[:dashboard][:db][:database]
        action :create_db
    end

    mysql_database "create dashboard database user" do
        host	mysql_address
        username "db_maker"
        password mysql[:mysql][:db_maker_password]
        database node[:dashboard][:db][:database]
        action :query
        sql "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER on #{node[:dashboard][:db][:database]}.* to '#{node[:dashboard][:db][:user]}'@'%' IDENTIFIED BY '#{node[:dashboard][:db][:password]}';"
    end

    db_settings = {
      'ENGINE' => "'django.db.backends.mysql'",
      'NAME' => "'#{node[:dashboard][:db][:database]}'",
      'USER' => "'#{node[:dashboard][:db][:user]}'",
      'PASSWORD' => "'#{node[:dashboard][:db][:password]}'",
      'HOST' => "'#{mysql_address}'",
      'default-character-set' => "'utf8'"
    }
elsif node[:nova_dashboard][:sql_engine] == "sqlite"
    Chef::Log.info("Configuring Horizion to use SQLite3 backend")
    db_settings = {
      'ENGINE' => "'django.db.backends.sqlite3'",
      'NAME' => "os.path.join(LOCAL_PATH, 'dashboard_openstack.sqlite3')"
    }
    
    file "/etc/openstack-dashboard/dashboard_openstack.sqlite3" do
        action :touch
        user "www-data"
        group "www-data"
    end
end

# Need to figure out environment filter
env_filter = " AND keystone_config_environment:keystone-config-#{node[:nova_dashboard][:keystone_instance]}"
keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
if keystones.length > 0
  keystone = keystones[0]
  keystone = node if keystone.name == node.name
else
  keystone = node
end

if node[:nova_dashboard][:use_gitrepo]
  pfs_and_install_deps "keystone" do
    cookbook "keystone"
    cnode keystone
  end
end

keystone_address = keystone["keystone"]["address"] rescue nil
keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
keystone_service_port = keystone["keystone"]["api"]["service_port"] rescue nil
Chef::Log.info("Keystone server found at #{keystone_address}")

execute "python manage.py syncdb" do
  cwd dashboard_path
  environment ({'PYTHONPATH' => dashboard_path})
  command "#{venv_prefix} python manage.py syncdb --noinput"
  user "www-data"
  action :nothing
  notifies :restart, resources(:service => "apache2"), :immediately
end

# Need to template the "EXTERNAL_MONITORING" array
template "#{dashboard_path}/openstack_dashboard/local/local_settings.py" do
  source "local_settings.py.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :keystone_address => keystone_address,
    :keystone_service_port => keystone_service_port,
    :db_settings => db_settings
  )
  notifies :run, resources(:execute => "python manage.py syncdb"), :immediately
  action :create
end

node[:nova_dashboard][:monitor][:svcs] <<["nova_dashboard-server"]
node.save

