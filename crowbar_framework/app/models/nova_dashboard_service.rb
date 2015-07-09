#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class NovaDashboardService < PacemakerServiceObject

  def initialize(thelogger)
    super(thelogger)
    @bc_name = "nova_dashboard"
  end

# Turn off multi proposal support till it really works and people ask for it.
  def self.allow_multiple_proposals?
    false
  end

  class << self
    def role_constraints
      {
        "nova_dashboard-server" => {
          "unique" => false,
          "count" => 1,
          "exclude_platform" => {
            "windows" => "/.*/"
          },
          "cluster" => true
        }
      }
    end
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "database", "inst" => role.default_attributes["nova_dashboard"]["database_instance"] }
    answer << { "barclamp" => "keystone", "inst" => role.default_attributes["nova_dashboard"]["keystone_instance"] }
    answer << { "barclamp" => "nova", "inst" => role.default_attributes["nova_dashboard"]["nova_instance"] }
    answer
  end

  def create_proposal
    @logger.debug("Nova_dashboard create_proposal: entering")
    base = super

    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }
    if nodes.size >= 1
      controller = nodes.find { |n| n.intended_role == "controller" } || nodes.first
      base["deployment"]["nova_dashboard"]["elements"] = {
        "nova_dashboard-server" => [ controller[:fqdn] ]
      }
    end

    base["attributes"][@bc_name]["database_instance"] = find_dep_proposal("database")
    base["attributes"][@bc_name]["keystone_instance"] = find_dep_proposal("keystone")
    base["attributes"][@bc_name]["nova_instance"] = find_dep_proposal("nova")

    base["attributes"][@bc_name][:db][:password] = random_password

    @logger.debug("Nova_dashboard create_proposal: exiting")
    base
  end

  def validate_proposal_after_save proposal
    validate_one_for_role proposal, "nova_dashboard-server"

    super
  end


  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Nova_dashboard apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    server_elements, server_nodes, ha_enabled = role_expand_elements(role, "nova_dashboard-server")

    vip_networks = ["admin", "public"]

    dirty = false
    dirty = prepare_role_for_ha_with_haproxy(role, ["nova_dashboard", "ha", "enabled"], ha_enabled, server_elements, vip_networks)
    role.save if dirty

    net_svc = NetworkService.new @logger
    # All nodes must have a public IP, even if part of a cluster; otherwise
    # the VIP can't be moved to the nodes
    server_nodes.each do |n|
      net_svc.allocate_ip "default", "public", "host", n
    end

    # No specific need to call sync dns here, as the cookbook doesn't require
    # the VIP of the cluster to be setup
    allocate_virtual_ips_for_any_cluster_in_networks(server_elements, vip_networks)

    # Make sure the nodes have a link to the dashboard on them.
    if role.default_attributes["nova_dashboard"]["apache"]["ssl"]
      protocol = "https"
    else
      protocol = "http"
    end

    if ha_enabled
      # This assumes that there can only be one cluster assigned to the
      # nova_dashboard-server role (otherwise, we'd need to check to which
      # cluster each node belongs to create the link).
      # Good news, the assumption is correct :-)
      public_db = Chef::DataBag.load("crowbar/public_network") rescue nil
      admin_db = Chef::DataBag.load("crowbar/admin_network") rescue nil

      hostname = nil
      server_elements.each do |element|
        if is_cluster? element
          hostname = PacemakerServiceObject.cluster_vhostname_from_element(element)
          break
        end
      end

      raise "Cannot find hostname for VIP of cluster" if hostname.nil?

      public_server_ip = public_db["allocated_by_name"]["#{hostname}"]["address"]
      admin_server_ip = admin_db["allocated_by_name"]["#{hostname}"]["address"]
    end

    server_nodes.each do |n|
      node = NodeObject.find_node_by_name(n)
      node.crowbar["crowbar"] ||= {}
      node.crowbar["crowbar"]["links"] ||= {}

      unless ha_enabled
        public_server_ip = node.get_network_by_type("public")["address"]
        admin_server_ip = node.get_network_by_type("admin")["address"]
      end

      node.crowbar["crowbar"]["links"].delete("Nova Dashboard (public)")
      node.crowbar["crowbar"]["links"]["OpenStack Dashboard (public)"] = "#{protocol}://#{public_server_ip}/"

      node.crowbar["crowbar"]["links"].delete("Nova Dashboard (admin)")
      node.crowbar["crowbar"]["links"]["OpenStack Dashboard (admin)"] = "#{protocol}://#{admin_server_ip}/"

      node.save
    end

    @logger.debug("Nova_dashboard apply_role_pre_chef_call: leaving")
  end

end

