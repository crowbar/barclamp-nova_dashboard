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


packages = [ "openstack-dashboard", "django-openstack", "openstackx", "python-django" ]
packages.each do |pkg|
  package pkg do
    action :install
  end
end

#directory "/var/lib/dash/.blackhole" do
#  owner "www-data"
#  mode "0755"
#  action :create
#end
  
apache_site "000-default" do
  enable false
end

apache_site "dash" do
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
end

# Need to figure out environment filter
env_filter = " AND keystone_config_environment:keystone-config-#{node[:nova_dashboard][:keystone_instance]}"
keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
if keystones.length > 0
  keystone = keystones[0]
  keystone = node if keystone.name = node.name
else
  keystone = node
end

keystone_address = keystone[:keystone][:address]
keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
Chef::Log.info("Keystone server found at #{keystone_address}")

execute "python dashboard/manage.py syncdb" do
  cwd "/var/lib/dash"
  environment ({'PYTHONPATH' => '/var/lib/dash/'})
  command "python dashboard/manage.py syncdb"
  action :nothing
  notifies :restart, resources(:service => "apache2"), :immediately
end

# Need to template the "EXTERNAL_MONITORING" array
template "/var/lib/dash/local/local_settings.py" do
  source "local_settings.py.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :keystone_admin_token => keystone[:keystone][:admin]['token'],
    :keystone_address => keystone_address,
    :db_settings => db_settings
  )
  notifies :run, resources(:execute => "python dashboard/manage.py syncdb"), :immediately
  action :create
end

node[:nova_dashboard][:monitor][:svcs] <<["nova_dashboard-server"]
node.save

