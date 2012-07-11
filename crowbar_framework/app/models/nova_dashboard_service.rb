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
    @bc_name = "nova_dashboard"
    @logger = thelogger
  end

  def self.allow_multiple_proposals?
    true
  end

  def proposal_dependencies(role)
    answer = []
    if role.default_attributes["nova_dashboard"]["sql_engine"] == "database"
      answer << { "barclamp" => "database", "inst" => role.default_attributes["nova_dashboard"]["sql_instance"] }
    end
    answer << { "barclamp" => "keystone", "inst" => role.default_attributes["nova_dashboard"]["keystone_instance"] }
    answer
  end

  def create_proposal
    @logger.debug("Nova_dashboard create_proposal: entering")
    base = super

    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }
    if nodes.size >= 1
      base["deployment"]["nova_dashboard"]["elements"] = {
        "nova_dashboard-server" => [ nodes.first[:fqdn] ]
      }
    end

    base["attributes"]["nova_dashboard"]["sql_instance"] = ""
    begin
      databaseService = DatabaseService.new(@logger)
      # Look for active roles
      dbs = databaseService.list_active[1]
      if dbs.empty?
        # No actives, look for proposals
        dbs = databaseService.proposals[1]
      end
      if dbs.empty?
        @logger.info("Dashboard create_proposal: no database proposal found")
        base["attributes"]["nova_dashboard"]["sql_engine"] = ""
      else
        base["attributes"]["nova_dashboard"]["sql_instance"] = dbs[0]
        base["attributes"]["nova_dashboard"]["sql_engine"] = "database"
      end
    rescue
      @logger.info("Nova dashboard create_proposal: no database found")
      base["attributes"]["nova_dashboard"]["sql_engine"] = ""
    end

    base["attributes"]["nova_dashboard"]["sql_engine"] = "sqlite" if base["attributes"]["nova_dashboard"]["sql_engine"] == ""

    base["attributes"]["nova_dashboard"]["show_swift"] = false
    begin
      swiftService = SwiftService.new(@logger)
      swifts = swiftService.list_active[1]
      if swifts.empty?
        # No actives, look for proposals
        swifts = swiftService.proposals[1]
      end
      if swifts.empty?
        base["attributes"]["nova_dashboard"]["show_swift"] = false
      else
        base["attributes"]["nova_dashboard"]["show_swift"] = true
      end
    rescue
      @logger.info("Nova dashboard create_proposal: no swift found")
      base["attributes"]["nova_dashboard"]["show_swift"] = false
    end

    base["attributes"]["nova_dashboard"]["keystone_instance"] = ""
    begin
      keystoneService = KeystoneService.new(@logger)
      keystones = keystoneService.list_active[1]
      if keystones.empty?
        # No actives, look for proposals
        keystones = keystoneService.proposals[1]
      end
      base["attributes"]["nova_dashboard"]["keystone_instance"] = keystones[0] unless keystones.empty?
    rescue
      @logger.info("Nova dashboard create_proposal: no keystone found")
    end

    @logger.debug("Nova_dashboard create_proposal: exiting")
    base
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
      server_ip = node.get_network_by_type("public")["address"]
      node.crowbar["crowbar"] = {} if node.crowbar["crowbar"].nil?
      node.crowbar["crowbar"]["links"] = {} if node.crowbar["crowbar"]["links"].nil?
      node.crowbar["crowbar"]["links"]["Nova Dashboard"] = "http://#{server_ip}/"
      node.save
    end
    @logger.debug("Nova_dashboard apply_role_pre_chef_call: leaving")
  end

end

