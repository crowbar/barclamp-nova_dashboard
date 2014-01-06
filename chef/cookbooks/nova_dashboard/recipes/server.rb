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
dashboard_path = "/usr/share/openstack-dashboard"

if node[:nova_dashboard][:apache][:ssl]
  include_recipe "apache2::mod_ssl"
end

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)


unless node[:nova_dashboard][:use_gitrepo]
  if %w(debian ubuntu).include?(node.platform)
    # Explicitly added client dependencies for now.
    packages = [ "python-lesscpy", "python-ply", "openstack-dashboard", "python-novaclient", "python-glance", "python-swift", "python-keystone", "openstackx", "python-django", "python-django-horizon", "python-django-nose" ]
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
  elsif %w(redhat centos).include?(node.platform)
    package "openstack-dashboard"
    package "python-memcached"
  else
    # On SUSE, the package has the correct list of dependencies
    package "openstack-dashboard"
  end
else
  venv_path = node[:nova_dashboard][:use_virtualenv] ? "#{dashboard_path}/.venv" : nil
  venv_prefix = node[:nova_dashboard][:use_virtualenv] ? ". #{venv_path}/bin/activate &&" : nil

  pfs_and_install_deps "nova_dashboard" do
    path dashboard_path
    virtualenv venv_path
  end

execute "chown_#{node[:apache][:user]}" do
  command "chown -R #{node[:apache][:user]}:#{node[:apache][:group]} #{dashboard_path}"
end

if node.platform != "suse"
  directory "#{dashboard_path}/.blackhole" do
    owner node[:apache][:user]
    group node[:apache][:group]
    mode "0755"
    action :create
  end
  
  directory "/var/www" do
    owner node[:apache][:user]
    group node[:apache][:group]
    mode "0755"
    action :create
  end

  apache_site "000-default" do
    enable false
  end

  file "/etc/apache2/conf.d/openstack-dashboard.conf" do
    action :delete
  end
else
  # Get rid of unwanted vhost config files:
  ["#{node[:apache][:dir]}/vhosts.d/default-redirect.conf",
   "#{node[:apache][:dir]}/vhosts.d/nova-dashboard.conf"].each do |f|
    file f do
      action :delete
    end
  end
end

template "#{node[:apache][:dir]}/sites-available/nova-dashboard.conf" do
  if node.platform == "suse"
    path "#{node[:apache][:dir]}/vhosts.d/openstack-dashboard.conf"
    source "nova-dashboard.conf.suse.erb"
  else
    source "nova-dashboard.conf.erb"
  end
  mode 0644
  variables(
    :horizon_dir => dashboard_path,
    :user => node[:apache][:user],
    :group => node[:apache][:group],
    :use_ssl => node[:nova_dashboard][:apache][:ssl],
    :ssl_crt_file => node[:nova_dashboard][:apache][:ssl_crt_file],
    :ssl_key_file => node[:nova_dashboard][:apache][:ssl_key_file],
    :ssl_crt_chain_file => node[:nova_dashboard][:apache][:ssl_crt_chain_file],
    :venv => node[:nova_dashboard][:use_virtualenv] && node[:nova_dashboard][:use_gitrepo],
    :venv_path => venv_path
  )
  if ::File.symlink?("#{node[:apache][:dir]}/sites-enabled/nova-dashboard.conf") or node.platform == "suse"
    notifies :reload, resources(:service => "apache2")
  end
end

if node[:nova_dashboard][:use_virtualenv] && node[:nova_dashboard][:use_gitrepo]
  template "/usr/share/openstack-dashboard/openstack_dashboard/wsgi/django_venv.wsgi" do
    source "django_venv.wsgi.erb"
    mode 0644
    variables(
      :venv_path => venv_path
    )
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

env_filter = " AND database_config_environment:database-config-#{node[:nova_dashboard][:database_instance]}"
sqls = search(:node, "roles:database-server#{env_filter}") || []
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
case backend_name
when "mysql"
    django_db_backend = "'django.db.backends.mysql'"
when "postgresql"
    django_db_backend = "'django.db.backends.postgresql_psycopg2'"
end

database_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(sql, "admin").address if database_address.nil?
Chef::Log.info("Database server found at #{database_address}")
db_conn = { :host => database_address,
            :username => "db_maker",
            :password => sql["database"][:db_maker_password] }


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
    host '%'
    provider db_user_provider
    action :create
end

database_user "grant database access for dashboard database user" do
    connection db_conn
    database_name node[:dashboard][:db][:database]
    username node[:dashboard][:db][:user]
    password node[:dashboard][:db][:password]
    host '%'
    privileges privs
    provider db_user_provider
    action :grant
end

db_settings = {
  'ENGINE' => django_db_backend,
  'NAME' => "'#{node[:dashboard][:db][:database]}'",
  'USER' => "'#{node[:dashboard][:db][:user]}'",
  'PASSWORD' => "'#{node[:dashboard][:db][:password]}'",
  'HOST' => "'#{database_address}'",
  'default-character-set' => "'utf8'"
}

# Need to figure out environment filter
env_filter = " AND keystone_config_environment:keystone-config-#{node[:nova_dashboard][:keystone_instance]}"
keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
if keystones.length > 0
  keystone = keystones[0]
  keystone = node if keystone.name == node.name
else
  keystone = node
end

keystone_host = keystone[:fqdn]
keystone_protocol = keystone["keystone"]["api"]["protocol"]
keystone_service_port = keystone["keystone"]["api"]["service_port"] rescue nil
keystone_insecure = keystone_protocol == 'https' && keystone[:keystone][:ssl][:insecure]
Chef::Log.info("Keystone server found at #{keystone_host}")

glances = search(:node, "roles:glance-server") || []
if glances.length > 0
  glance = glances[0]
  glance_insecure = glance[:glance][:api][:protocol] == 'https' && glance[:glance][:ssl][:insecure]
else
  glance_insecure = false
end

cinders = search(:node, "roles:cinder-controller") || []
if cinders.length > 0
  cinder = cinders[0]
  cinder_insecure = cinder[:cinder][:api][:protocol] == 'https' && cinder[:cinder][:ssl][:insecure]
else
  cinder_insecure = false
end

neutrons = search(:node, "roles:neutron-server") || []
if neutrons.length > 0
  neutron = neutrons[0]
  neutron_insecure = neutron[:neutron][:api][:protocol] == 'https' && neutron[:neutron][:ssl][:insecure]
else
  neutron_insecure = false
end

env_filter = "AND nova_config_environment:nova-config-#{node[:nova_dashboard][:nova_instance]}"
novas = search(:node, "roles:nova-multi-controller #{env_filter}") || []
if novas.length > 0
  nova = novas[0]
  nova_insecure = nova[:nova][:ssl][:enabled] && nova[:nova][:ssl][:insecure]
else
  nova_insecure = false
end

directory "/var/lib/openstack-dashboard" do
  owner node[:apache][:user]
  group node[:apache][:group]
  mode "0700"
  action :create
end


execute "python manage.py syncdb" do
  cwd dashboard_path
  environment ({'PYTHONPATH' => dashboard_path})
  command "#{venv_prefix} python manage.py syncdb --noinput"
  user node[:apache][:user]
  action :nothing
  notifies :restart, resources(:service => "apache2"), :immediately
end


# We're going to use memcached as a cache backend for Django
#
# Do not use the default port, since this will collide with swift
# if it happens to be installed on the same node
memcached_instance "nova-dashboard" do
  port node[:nova_dashboard][:memcached][:port]
end

case node[:platform]
when "suse"
  package "python-python-memcached"
when "debian", "ubuntu"
  package "python-memcache"
end

# Need to template the "EXTERNAL_MONITORING" array
template "#{dashboard_path}/openstack_dashboard/local/local_settings.py" do
  source "local_settings.py.erb"
  owner node[:apache][:user]
  group "root"
  mode "0640"
  variables(
    :debug => node[:nova_dashboard][:debug],
    :keystone_protocol => keystone_protocol,
    :keystone_host => keystone_host,
    :keystone_service_port => keystone_service_port,
    :insecure => keystone_insecure || glance_insecure || cinder_insecure || neutron_insecure || nova_insecure,
    :db_settings => db_settings,
    :compress_offline => node.platform == "suse",
    :timezone => (node[:provisioner][:timezone] rescue "UTC") || "UTC",
    :use_ssl => node[:nova_dashboard][:apache][:ssl],
    :site_branding => node[:nova_dashboard][:site_branding]
  )
  notifies :run, resources(:execute => "python manage.py syncdb"), :immediately
  action :create
end

node[:nova_dashboard][:monitor][:svcs] <<["nova_dashboard-server"]
node.save

