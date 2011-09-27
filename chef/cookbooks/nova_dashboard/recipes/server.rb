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

packages = [ "git, "python-django", "django-openstack", "openstackx" ]
packages.each do |pkg|
  package pkg do
    action :install
  end
end

directory "/var/lib/dash" do
  owner "www-data"
  mode "0755"
  action :create
end
  
directory "/var/lib/dash/.blackhole" do
  owner "www-data"
  mode "0755"
  action :create
end
  
template "/var/lib/dash/dashboard/wsgi/django.wsgi" do
  source "django.wsgi"
  action :create
end

directory var/lib/dash/local" do
  owner "www-data"
  mode "0755"
  action :create
end

link "/var/lib/dash/dashboard/local" do
  to "/var/lib/dash/local"
  action :create
end

template "/var/lib/dash/local/local_settings.py" do
  action :create
  source "local_settings.py.erb"
  owner  "www-data"
end

bash "dash-db" do
  code <<-EOH
PATH="/usr/bin:/bin"
python /var/lib/dash/dashboard/manage.py syncdb
EOH
  user "www-data"
  action :nothing
end

file "/var/lib/dash/local/dashboard_openstack.sqlite3" do
  owner "www-data"
  mode "0600"
  action :create
  notifies :run, "bash[dash-d]"
end

web_app "nova_dashboard" do
  server_name "nova_dashboard"
  docroot "/var/lib/dash/.blackhole"
  template "web_app.conf.erb"
  web_port 80
end

node[:nova_dashboard][:monitor][:svcs] <<["nova_dashboard-server"]
node.save

