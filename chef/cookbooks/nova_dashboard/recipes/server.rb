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

if node.platform == "suse"
  dashboard_path = "/var/lib/openstack-dashboard"
else
  dashboard_path = "/usr/share/openstack-dashboard" 
end

# Explicitly added client dependencies for now.
packages = [ "openstack-dashboard", "python-novaclient", "python-glance", "python-swift", "python-keystone", "openstackx", "python-django", "python-django-horizon", "python-django-nose" ]
packages = [ "openstack-dashboard", "python-novaclient", "python-glance", "openstack-swift", "python-keystone", "python-django", "python-horizon", "python-django-nose" ] if node.platform == "suse"
packages.each do |pkg|
  package pkg do
    action :install
  end
end

if node.platform != "suse"
  directory "/usr/share/openstack-dashboard/.blackhole" do
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
end

apache_site "000-default" do
  enable false
end

template "#{node[:apache][:dir]}/sites-available/nova-dashboard.conf" do
  if node.platform == "suse"
    path "#{node[:apache][:dir]}/vhosts.d/nova-dashboard.conf"
    source "nova-dashboard.conf.suse.erb"
  else
    source "nova-dashboard.conf.erb"
  end
  mode 0644
  variables(
      :horizon_dir => dashboard_path,
      :user => node[:apache][:user],
      :group => node[:apache][:group]
  )
  if ::File.symlink?("#{node[:apache][:dir]}/sites-enabled/nova-dashboard.conf") or node.platform == "suse"
    notifies :reload, resources(:service => "apache2")
  end
end

apache_site "nova-dashboard.conf" do
  enable true
end

node.set_unless['dashboard']['db']['password'] = secure_password

sql_engine = node[:nova_dashboard][:sql_engine]

db_provider = nil
db_user_provider = nil
privs = nil

if sql_engine == "mysql"
    package "python-mysqldb" do
        package_name "python-mysql" if node.platform == "suse"
        action :install
    end

    db_provider = Chef::Provider::Database::Mysql
    db_user_provider = Chef::Provider::Database::MysqlUser
    privs = [ "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE",
              "DROP", "INDEX", "ALTER" ]
    django_db_backend = "'django.db.backends.mysql'"
elsif sql_engine == "postgresql"
    package "python-psycopg2" do
         action :install
    end

    db_provider = Chef::Provider::Database::Postgresql
    db_user_provider = Chef::Provider::Database::PostgresqlUser
    privs = [ "CREATE", "CONNECT", "TEMP" ]
    django_db_backend = "'django.db.backends.postgresql_psycopg2'"
end

if node[:nova_dashboard][:sql_engine] == "sqlite"
   Chef::Log.info("Configuring Horizion to use SQLite3 backend")
    db_settings = {
      'ENGINE' => "'django.db.backends.sqlite3'",
      'NAME' => "os.path.join(LOCAL_PATH, 'dashboard_openstack.sqlite3')"
    }
else
    Chef::Log.info("Configuring Horizion to use #{sql_engine} backend")
    include_recipe "#{sql_engine}::client"

    env_filter = " AND #{sql_engine}_config_environment:#{sql_engine}-config-#{node[:nova_dashboard][:sql_instance]}"
    sqls = search(:node, "roles:#{sql_engine}-server#{env_filter}") || []
    if sqls.length > 0
        sql = sqls[0]
        sql = node if sql.name == node.name
    else
        sql = node
    end

    sql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(sql, "admin").address if sql_address.nil?
    Chef::Log.info("#{sql_engine} server found at #{sql_address}")
    db_conn = { :host => sql_address,
                :username => "db_maker",
                :password => sql[sql_engine][:db_maker_password] }


    # Create the Dashboard Database
    database "create #{node[:dashboard][:db][:database]} database" do
        connection db_conn
        database_name node[:dashboard][:db][:database]
        provider db_provider
        action :create
    end
 
    database_user "create dashboard database user" do
        connection db_conn
        database_name node[:dashboard][:db][:database]
        username node[:dashboard][:db][:user]
        password node[:dashboard][:db][:password]
        provider db_user_provider
        action :create
    end

    database_user "create dashboard database user" do
        connection db_conn
        database_name node[:dashboard][:db][:database]
        username node[:dashboard][:db][:user]
        password node[:dashboard][:db][:password]
        host sql_address
        privileges privs
        provider db_user_provider
        action :grant
    end

    db_settings = {
      'ENGINE' => django_db_backend,
      'NAME' => "'#{node[:dashboard][:db][:database]}'",
      'USER' => "'#{node[:dashboard][:db][:user]}'",
      'PASSWORD' => "'#{node[:dashboard][:db][:password]}'",
      'HOST' => "'#{sql_address}'",
      'default-character-set' => "'utf8'"
    }
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

keystone_address = keystone["keystone"]["address"] rescue nil
keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
keystone_admin_port = keystone["keystone"]["api"]["admin_port"] rescue nil
keystone_service_port = keystone["keystone"]["api"]["service_port"] rescue nil
Chef::Log.info("Keystone server found at #{keystone_address}")

execute "python manage.py syncdb" do
  cwd dashboard_path
  environment ({'PYTHONPATH' => dashboard_path})
  command "python manage.py syncdb"
  user node[:apache][:user]
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
    :keystone_admin_port => keystone_admin_port,
    :db_settings => db_settings
  )
  notifies :run, resources(:execute => "python manage.py syncdb"), :immediately
  action :create
end

node[:nova_dashboard][:monitor][:svcs] <<["nova_dashboard-server"]
node.save

