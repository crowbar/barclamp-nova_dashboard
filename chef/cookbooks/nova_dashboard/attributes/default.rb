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

default[:dashboard][:db][:database] = "dash"
default[:dashboard][:db][:user] = "dash"
default[:dashboard][:db][:password] = "" # Set by Recipe

default[:nova_dashboard][:debug] = false
default[:nova_dashboard][:site_branding] = "OpenStack Dashboard"

default[:nova_dashboard][:apache][:ssl] = false
default[:nova_dashboard][:apache][:ssl_crt_file] = '/etc/apache2/ssl.crt/openstack-dashboard-server.crt'
default[:nova_dashboard][:apache][:ssl_key_file] = '/etc/apache2/ssl.key/openstack-dashboard-server.key'
default[:nova_dashboard][:apache][:ssl_crt_chain_file] = ''

# declare what needs to be monitored
node.set[:nova_dashboard][:monitor]={}
node.set[:nova_dashboard][:monitor][:svcs] = []
node.set[:nova_dashboard][:monitor][:ports]={}

# Use a non-default port for memcached to avoid collision with swift
node[:nova_dashboard][:memcached] = {}
node[:nova_dashboard][:memcached][:port] = 11212
