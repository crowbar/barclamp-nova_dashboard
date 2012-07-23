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

override[:nova_dashboard][:user]="nova_dashboard"
default[:nova_dashboard][:site_branding] = "Openstack Nova Dashboard"
default[:nova_dashboard][:show_swift] = false

# declare what needs to be monitored
node[:nova_dashboard][:monitor]={}
node[:nova_dashboard][:monitor][:svcs] = []
node[:nova_dashboard][:monitor][:ports]={}

# Secure Apache config
default[:nova_dashboard][:apache][:use_http] = true # Provide dashboard vhost on port 80
default[:nova_dashboard][:apache][:use_https] = false # Provide dashboard vhost on port 443
default[:nova_dashboard][:apache][:redirect_to_https] = false # Redirect all requests to port 443
default[:nova_dashboard][:apache][:ssl_crt_file] = '/etc/apache2/ssl.crt/openstack-dashboard-server.crt'
default[:nova_dashboard][:apache][:ssl_key_file] = '/etc/apache2/ssl.key/openstack-dashboard-server.key'

# SSL certificate verification, disable when using self-signed certificates
default[:nova_dashboard][:ssl_no_verify] = false
