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

mysql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(mysql, "admin").address if mysql_address.nil?
Chef::Log.info("Mysql server found at #{mysql_address}")

keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
Chef::Log.info("Rabbit server found at #{rabbit_address}")

# Need to template the "EXTERNAL_MONITORING" array
template "/var/lib/dash/local/local_settings.py" do
  source "local_settings.py.erb"
  variables(
    :user => node[:dash][:db_user],
    :passwd => node[:dash][:db_passwd],
    :keystone_address => keystone_address,
    :mysql_address => mysql_address,
    :ip_address => node[:controller_ipaddress],
    :db_name => node[:dash][:db]
  )
  action :create
#  owner  "www-data"
end

execute "PYTHONPATH=/var/lib/dash/ python dashboard/manage.py syncdb" do
  cwd "/var/lib/dash"
  environment ({'PYTHONPATH' => '/var/lib/dash/'})
  command "python dashboard/manage.py syncdb"
  action :run
  notifies :restart, resources(:service => "apache2"), :immediately
end

#bash "dash-db" do
#  code <<-EOH
#PATH="/usr/bin:/bin"
#python /var/lib/dash/dashboard/manage.py syncdb
#EOH
#  user "www-data"
#  action :nothing
#end

#file "/var/lib/dash/local/dashboard_openstack.sqlite3" do
#  owner "www-data"
#  mode "0600"
#  action :create
#  notifies :run, "bash[dash-db]"
#end

apache_site "000-default" do
  enable false
end

apache_site "dash" do
  enable true
end

#web_app "nova_dashboard" do
#  server_name "nova_dashboard"
#  docroot "/var/lib/dash/.blackhole"
#  template "web_app.conf.erb"
#  web_port 80
#end

node[:nova_dashboard][:monitor][:svcs] <<["nova_dashboard-server"]
node.save

