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
# This is required for the OCF resource agent
include_recipe "apache2::mod_status"

if %w(suse).include? node.platform
  dashboard_path = "/srv/www/openstack-dashboard"
else
  dashboard_path = "/usr/share/openstack-dashboard"
end

if node[:nova_dashboard][:apache][:ssl]
  include_recipe "apache2::mod_ssl"
end

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
    package "python-lesscpy"
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

  template "/etc/logrotate.d/openstack-dashboard" do
    source "nova-dashboard.logrotate.erb"
    mode 0644
    owner "root"
    group "root"
  end

  apache_module "deflate" do
    conf false
    enable true
  end
end

ha_enabled = node[:nova_dashboard][:ha][:enabled]

if ha_enabled
  log "HA support for horizon is enabled"
  admin_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
  bind_host = admin_address
  bind_port = node[:nova_dashboard][:ha][:ports][:plain]
  bind_port_ssl = node[:nova_dashboard][:ha][:ports][:ssl]

  include_recipe "nova_dashboard::ha"
else
  log "HA support for horizon is disabled"
  bind_host = "*"
  bind_port = 80
  bind_port_ssl = 443
end

if node[:nova_dashboard][:apache][:ssl]
  node.default[:apache][:listen_ports] = [bind_port, bind_port_ssl]
else
  node.default[:apache][:listen_ports] = [bind_port]
end

# Override what the apache2 cookbook does since it enforces the ports
resource = resources(:template => "#{node[:apache][:dir]}/ports.conf")
resource.variables({:apache_listen_ports => node[:apache][:listen_ports]})

template "#{node[:apache][:dir]}/sites-available/nova-dashboard.conf" do
  if node.platform == "suse"
    path "#{node[:apache][:dir]}/vhosts.d/openstack-dashboard.conf"
  end
  source "nova-dashboard.conf.erb"
  mode 0644
  variables(
    :bind_host => bind_host,
    :bind_port => bind_port,
    :bind_port_ssl => bind_port_ssl,
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

apache_site "nova-dashboard.conf" do
  enable true
end

sql = get_instance('roles:database-server')
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

database_address = CrowbarDatabaseHelper.get_listen_address(sql)
Chef::Log.info("Database server found at #{database_address}")
db_conn = { :host => database_address,
            :username => "db_maker",
            :password => sql["database"][:db_maker_password] }

crowbar_pacemaker_sync_mark "wait-nova_dashboard_database"

# Create the Dashboard Database
database "create #{node[:nova_dashboard][:db][:database]} database" do
    connection db_conn
    database_name node[:nova_dashboard][:db][:database]
    provider db_provider
    action :create
end

database_user "create dashboard database user" do
    connection db_conn
    database_name node[:nova_dashboard][:db][:database]
    username node[:nova_dashboard][:db][:user]
    password node[:nova_dashboard][:db][:password]
    host '%'
    provider db_user_provider
    action :create
end

database_user "grant database access for dashboard database user" do
    connection db_conn
    database_name node[:nova_dashboard][:db][:database]
    username node[:nova_dashboard][:db][:user]
    password node[:nova_dashboard][:db][:password]
    host '%'
    privileges privs
    provider db_user_provider
    action :grant
end

crowbar_pacemaker_sync_mark "create-nova_dashboard_database"

db_settings = {
  'ENGINE' => django_db_backend,
  'NAME' => "'#{node[:nova_dashboard][:db][:database]}'",
  'USER' => "'#{node[:nova_dashboard][:db][:user]}'",
  'PASSWORD' => "'#{node[:nova_dashboard][:db][:password]}'",
  'HOST' => "'#{database_address}'",
  'default-character-set' => "'utf8'"
}

keystone = get_instance('roles:keystone-server')
keystone_settings = KeystoneHelper.keystone_settings(keystone)
Chef::Log.info("Keystone server found at #{keystone_settings['internal_url_host']}")

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
  neutron_networking_plugin = neutron[:neutron][:networking_plugin]
  neutron_use_ml2 = neutron[:neutron][:use_ml2]
else
  neutron_insecure = false
  neutron_networking_plugin = ""
  neutron_use_ml2 = false
end

nova = get_instance('roles:nova-multi-controller')
nova_insecure = (nova[:nova][:ssl][:enabled] && nova[:nova][:ssl][:insecure]) rescue false

directory "/var/lib/openstack-dashboard" do
  owner node[:apache][:user]
  group node[:apache][:group]
  mode "0700"
  action :create
end


# We should protect this with crowbar_pacemaker_sync_mark, but because we run
# this in a notification, we can't; we had a sync mark earlier on, though, so
# the founder is very likely to do the db sync first and make this a non-issue.
execute "python manage.py syncdb" do
  cwd dashboard_path
  environment ({'PYTHONPATH' => dashboard_path})
  command "#{venv_prefix} python manage.py syncdb --noinput"
  user node[:apache][:user]
  group node[:apache][:group]
  action :nothing
  notifies :restart, resources(:service => "apache2"), :immediately
end


# We're going to use memcached as a cache backend for Django

# make sure our memcache only listens on the admin IP address
node_admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
node[:memcached][:listen] = node_admin_ip

if ha_enabled
  memcached_nodes = CrowbarPacemakerHelper.cluster_nodes(node, "nova_dashboard-server")
  memcached_locations = memcached_nodes.map do |n|
    node_admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(n, "admin").address
    "#{node_admin_ip}:#{n[:memcached][:port] rescue node[:memcached][:port]}"
  end
else
  memcached_locations = [ "#{node_admin_ip}:#{node[:memcached][:port]}" ]
end
memcached_locations.sort!

memcached_instance "nova-dashboard"
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
    :keystone_settings => keystone_settings,
    :insecure => keystone_settings['insecure'] || glance_insecure || cinder_insecure || neutron_insecure || nova_insecure,
    :db_settings => db_settings,
    :timezone => (node[:provisioner][:timezone] rescue "UTC") || "UTC",
    :use_ssl => node[:nova_dashboard][:apache][:ssl],
    :password_validator_regex => node[:nova_dashboard][:password_validator][:regex],
    :password_validator_help_text => node[:nova_dashboard][:password_validator][:help_text],
    :site_branding => node[:nova_dashboard][:site_branding],
    :neutron_networking_plugin => neutron_networking_plugin,
    :neutron_use_ml2 => neutron_use_ml2,
    :session_timeout => node[:nova_dashboard][:session_timeout],
    :memcached_locations => memcached_locations,
    :can_set_password => node["nova_dashboard"]["can_set_password"]
  )
  notifies :run, resources(:execute => "python manage.py syncdb"), :immediately
  action :create
end

node[:nova_dashboard][:monitor][:svcs] <<["nova_dashboard-server"]
node.save

