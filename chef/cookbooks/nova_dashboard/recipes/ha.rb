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

haproxy_servers, haproxy_servers_nodes  = PacemakerHelper.haproxy_servers(node, "nova_dashboard-server")
haproxy_servers.each do |haproxy_server|
  haproxy_server_node = haproxy_servers_nodes[haproxy_server['name']]
  haproxy_server['address'] = Chef::Recipe::Barclamp::Inventory.get_network_by_type(haproxy_server_node, "admin").address
  if node[:nova_dashboard][:apache][:ssl]
    haproxy_server['port'] = haproxy_server_node[:nova_dashboard][:ha][:ports][:ssl]
  else
    haproxy_server['port'] = haproxy_server_node[:nova_dashboard][:ha][:ports][:plain]
  end
end

if node[:nova_dashboard][:apache][:ssl]
  listen_port = 443
else
  listen_port = 80
end

haproxy_loadbalancer "nova_dashboard-service" do
  address "0.0.0.0"
  port listen_port
  use_ssl node[:nova_dashboard][:apache][:ssl]
  servers haproxy_servers
  action :nothing
end.run_action(:create)
