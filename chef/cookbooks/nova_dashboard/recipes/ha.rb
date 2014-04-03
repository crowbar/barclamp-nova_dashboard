# Copyright 2014 SUSE
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

haproxy_loadbalancer "horizon" do
  address "0.0.0.0"
  port 80
  use_ssl false
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "nova_dashboard", "nova_dashboard-server", "plain")
  action :nothing
end.run_action(:create)

if node[:nova_dashboard][:apache][:ssl]
  haproxy_loadbalancer "horizon-ssl" do
    address "0.0.0.0"
    port 443
    use_ssl true
    servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "nova_dashboard", "nova_dashboard-server", "ssl")
    action :nothing
  end.run_action(:create)
end

# Wait for all nodes to reach this point so we know that all nodes will have
# all the required packages installed before we create the pacemaker
# resources
crowbar_pacemaker_sync_mark "sync-nova_dashboard_before_ha"

# Avoid races when creating pacemaker resources
crowbar_pacemaker_sync_mark "wait-nova_dashboard_ha_resources"

agent_name = "ocf:heartbeat:apache"
apache_op = {}
apache_op["monitor"] = {}
apache_op["monitor"]["interval"] = "10s"

admin_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
if node[:nova_dashboard][:apache][:ssl]
  testurl = "https://#{admin_address}:#{node[:nova_dashboard][:ha][:ports][:ssl]}"
else
  testurl = "http://#{admin_address}:#{node[:nova_dashboard][:ha][:ports][:plain]}"
end

service_name = "apache2-service"

pacemaker_primitive service_name do
  agent agent_name
  params ({
    "statusurl" => "http://127.0.0.1:#{node[:nova_dashboard][:ha][:ports][:plain]}/server-status",
    "testurl" => testurl,
    "testregex10" => ".*<h3>Log In</h3>.*",
    # do not fail because of wrong certificates
    "client" => "curl --insecure"
  })
  op    apache_op
  action :create
end

pacemaker_clone "clone-#{service_name}" do
  rsc service_name
  action [ :create, :start ]
end

crowbar_pacemaker_sync_mark "create-nova_dashboard_ha_resources"

# Override service provider for apache2 resource defined in apache2 cookbook
resource = resources(:service => "apache2")
resource.provider(Chef::Provider::CrowbarPacemakerService)
