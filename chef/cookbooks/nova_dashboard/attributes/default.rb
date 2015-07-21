# Copyright 2011, Dell, Inc., Inc.
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

default[:nova_dashboard][:db][:database] = "horizon"
default[:nova_dashboard][:db][:user] = "horizon"
default[:nova_dashboard][:db][:password] = nil # must be set by wrapper

default[:nova_dashboard][:debug] = false
default[:nova_dashboard][:site_branding] = "OpenStack Dashboard"
default[:nova_dashboard][:site_theme] = ""
default[:nova_dashboard][:site_branding_link] = ""
default[:nova_dashboard][:help_url] = "http://docs.openstack.org/"

default[:nova_dashboard][:policy_file_path] = ""

default[:nova_dashboard][:policy_file][:identity] = "keystone_policy.json"
default[:nova_dashboard][:policy_file][:compute] = "nova_policy.json"
default[:nova_dashboard][:policy_file][:volume] = "cinder_policy.json"
default[:nova_dashboard][:policy_file][:image] = "glance_policy.json"
default[:nova_dashboard][:policy_file][:orchestration] = "heat_policy.json"
default[:nova_dashboard][:policy_file][:network] = "neutron_policy.json"

default[:nova_dashboard][:apache][:ssl] = false
default[:nova_dashboard][:apache][:ssl_crt_file] = '/etc/apache2/ssl.crt/openstack-dashboard-server.crt'
default[:nova_dashboard][:apache][:ssl_key_file] = '/etc/apache2/ssl.key/openstack-dashboard-server.key'
default[:nova_dashboard][:apache][:ssl_crt_chain_file] = ''

default[:nova_dashboard][:ha][:enabled] = false
# Ports to bind to when haproxy is used for the real ports
default[:nova_dashboard][:ha][:ports][:plain] = 5580
default[:nova_dashboard][:ha][:ports][:ssl] = 5581

# declare what needs to be monitored
node[:nova_dashboard][:monitor]={}
node[:nova_dashboard][:monitor][:svcs] = []
node[:nova_dashboard][:monitor][:ports]={}

default["nova_dashboard"]["can_set_mount_point"] = false
# Display password fields for Nova password injection
default["nova_dashboard"]["can_set_password"] = false

# Transient attribute.  Remove it when all OpenStack is deployed with
# Keystone v3
default["nova_dashboard"]["use_keystone_v3"] = false
