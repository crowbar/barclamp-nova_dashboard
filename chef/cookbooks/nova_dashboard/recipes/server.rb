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

if node[:nova_dashboard][:apache_use_https]
  include_recipe "apache2::mod_ssl"
end

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
      :group => node[:apache][:group],
      :use_http => node[:nova_dashboard][:apache][:use_http],
      :use_https => node[:nova_dashboard][:apache][:use_https],
      :redirect_to_https => node[:nova_dashboard][:apache][:redirect_to_https],
      :ssl_crt_file => node[:nova_dashboard][:apache][:ssl_crt_file],
      :ssl_key_file => node[:nova_dashboard][:apache][:ssl_key_file]
  )
  if ::File.symlink?("#{node[:apache][:dir]}/sites-enabled/nova-dashboard.conf") or node.platform == "suse"
    notifies :reload, resources(:service => "apache2")
  end
end

if node.platform == "suse"
  template "/etc/logrotate.d/openstack-dashboard" do
    source "nova-dashboard.logrotate.erb"
    mode 0644
    owner "root"
    group "root"
  end
end

apache_site "nova-dashboard.conf" do
  enable true
end

node.set_unless['dashboard']['db']['password'] = secure_password

sql_engine = node[:nova_dashboard][:sql_engine]
url_scheme = ""

if sql_engine == "database"
    Chef::Log.info("Configuring Horizion to use #{sql_engine} backend")

    env_filter = " AND #{sql_engine}_config_environment:#{sql_engine}-config-#{node[:nova_dashboard][:sql_instance]}"
    sqls = search(:node, "roles:#{sql_engine}-server#{env_filter}") || []
    if sqls.length > 0
        sql = sqls[0]
        sql = node if sql.name == node.name
    else
        sql = node
    end
    include_recipe "database::client"
    backend_name = Chef::Recipe::Database::Util.get_backend_name(sql)
    include_recipe "#{backend_name}::client"
    include_recipe "#{backend_name}::python-client"

    db_provider = Chef::Recipe::Database::Util.get_database_provider(sql)
    db_user_provider = Chef::Recipe::Database::Util.get_user_provider(sql)
    privs = Chef::Recipe::Database::Util.get_default_priviledges(sql)
    url_scheme = backend_name
    case backend_name
    when "mysql"
        django_db_backend = "'django.db.backends.mysql'"
    when "postgresql"
        django_db_backend = "'django.db.backends.postgresql_psycopg2'"
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
  keystone = node if keystone.name == node.name
else
  keystone = node
end

keystone_address = keystone["keystone"]["address"] rescue nil
keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
keystone_protocol = keystone["keystone"]["api"]["protocol"]
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
  owner "wwwrun"
  group "root"
  mode "0640"
  variables(
    :keystone_protocol => keystone_protocol,
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

