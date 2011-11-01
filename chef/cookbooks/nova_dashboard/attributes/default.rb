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

# declare what needs to be monitored
node[:nova_dashboard][:monitor]={}
node[:nova_dashboard][:monitor][:svcs] = []
node[:nova_dashboard][:monitor][:ports]={}

