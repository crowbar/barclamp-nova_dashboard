# Copyright 2011, Dell, Inc. 
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#  http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License. 
# 

class NovaDashboardService < ServiceObject

  def initialize(thelogger)
    super(thelogger)
    @bc_name = "nova_dashboard"
  end

# Turn off multi proposal support till it really works and people ask for it.
  def self.allow_multiple_proposals?
    false
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "database", "inst" => role.default_attributes["nova_dashboard"]["database_instance"] }
    if role.default_attributes[@bc_name]["use_gitrepo"]
      answer << { "barclamp" => "git", "inst" => role.default_attributes[@bc_name]["git_instance"] }
    end
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

    base["attributes"][@bc_name]["git_instance"] = find_dep_proposal("git", true)
    base["attributes"][@bc_name]["database_instance"] = find_dep_proposal("database")
    base["attributes"][@bc_name]["keystone_instance"] = find_dep_proposal("keystone")
    base["attributes"][@bc_name]["nova_instance"] = find_dep_proposal("nova")

    @logger.debug("Nova_dashboard create_proposal: exiting")
    base
  end

  def validate_proposal_after_save proposal
    validate_one_for_role proposal, "nova_dashboard-server"

    if proposal["attributes"][@bc_name]["use_gitrepo"]
      validate_dep_proposal_is_active "git", proposal["attributes"][@bc_name]["git_instance"]
    end

    super
  end


  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Nova_dashboard apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    net_svc = NetworkService.new @logger
    all_nodes.each do |n|
      net_svc.allocate_ip "default", "public", "host", n
    end

    # Make sure the nodes have a link to the dashboard on them.
    all_nodes.each do |n|
      node = NodeObject.find_node_by_name(n)
      public_server_ip = node.get_network_by_type("public")["address"]
      node.crowbar["crowbar"] = {} if node.crowbar["crowbar"].nil?
      node.crowbar["crowbar"]["links"] = {} if node.crowbar["crowbar"]["links"].nil?
      node.crowbar["crowbar"]["links"]["Nova Dashboard (public)"] = "http://#{public_server_ip}/"
      admin_server_ip = node.get_network_by_type("admin")["address"]
      node.crowbar["crowbar"]["links"]["Nova Dashboard (admin)"] = "http://#{admin_server_ip}/"
      node.save
    end
    @logger.debug("Nova_dashboard apply_role_pre_chef_call: leaving")
  end

end

