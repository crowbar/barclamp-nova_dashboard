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
include_recipe "mysql::client"

packages = [ "openstack-dashboard", "django-openstack", "openstackx", "python-django", "python-mysqldb" ]
packages.each do |pkg|
  package pkg do
    action :install
  end
end

#directory "/var/lib/dash" do
#  owner "www-data"
#  mode "0755"
#  action :create
#end
  
#directory "/var/lib/dash/.blackhole" do
#  owner "www-data"
#  mode "0755"
#  action :create
#end
  
#directory "var/lib/dash/local" do
#  owner "www-data"
#  mode "0755"
#  action :create
#end

#link "/var/lib/dash/dashboard/local" do
#  to "/var/lib/dash/local"
#  action :create
#end

apache_site "000-default" do
  enable false
end

apache_site "dash" do
  enable true
end

mysqls = search(:node, "recipes:mysql\\:\\:server") || []
if mysqls.length > 0
  mysql = mysqls[0]
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
  sql "GRANT ALL on #{node[:dashboard][:db][:database]}.* to '#{node[:dashboard][:db][:user]}'@'%' IDENTIFIED BY '#{node[:dashboard][:db][:password]}';"
end

# Need to figure out environment filter
keystones = search(:node, "recipes:keystone\\:\\:server") || []
if keystones.length > 0
  keystone = keystones[0]
else
  keystone = node
end

keystone_address = keystone[:keystone][:address]
keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
Chef::Log.info("Keystone server found at #{keystone_address}")

# Need to template the "EXTERNAL_MONITORING" array
template "/var/lib/dash/local/local_settings.py" do
  source "local_settings.py.erb"
  variables(
    :keystone_admin_token => keystone[:keystone][:dashboard][:long-lived-token],
    :keystone_address => keystone_address,
    :mysql_address => mysql_address,
    :mysql_db_name => node[:dashboard][:db][:database],
    :mysql_user => node[:dashboard][:db][:user],
    :mysql_passwd => node[:dashboard][:db][:passwd]
  )
  notifies :run, resources(:execute => "dashboard/manage.py syncdb"), :immediately
  action :create
end

execute "dashboard/manage.py syncdb" do
  cwd "/var/lib/dash"
  environment ({'PYTHONPATH' => '/var/lib/dash/'})
  command "python dashboard/manage.py syncdb"
  action :nothing
  notifies :restart, resources(:service => "apache2"), :immediately
end

node[:nova_dashboard][:monitor][:svcs] <<["nova_dashboard-server"]
node.save

