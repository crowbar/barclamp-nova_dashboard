#
# Copyright 2011, Dell, Inc.
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
# Author: andi abes
#

####
# if monitored by nagios, install the nrpe commands

# Node addresses are dynamic and can't be set from attributes only.
node[:nova_dashboard][:monitor][:ports]["nova_dashboard-server"] = [node[:nova_dashboard][:api_bind_host], node[:nova_dashboard][:api_bind_port]]

svcs = node[:nova_dashboard][:monitor][:svcs]
ports = node[:nova_dashboard][:monitor][:ports]

log ("will monitor nova_dashboard svcs: #{svcs.join(',')} and ports #{ports.values.join(',')}")

use_nagios = node["roles"].include?("nagios-client")
use_nagios = false if svcs.size == 0 and ports.size == 0

if use_nagios
  include_recipe "nagios::common"

  template "/etc/nagios/nrpe.d/nova_dashboard_nrpe.cfg" do
    source "nova_dashboard_nrpe.cfg.erb"
    mode "0644"
    group node[:nagios][:group]
    owner node[:nagios][:user]
    variables( {
      :svcs => svcs,
      :ports => ports
    })    
    notifies :restart, "service[nagios-nrpe-server]"
  end
end

