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
    sql_engine = role.default_attributes["nova_dashboard"]["sql_engine"]
    if sql_engine == "mysql" or sql_engine == "postgresql"
      answer << { "barclamp" => sql_engine, "inst" => role.default_attributes["nova_dashboard"]["sql_instance"] }
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
      mysqlService = MysqlService.new(@logger)
      # Look for active roles
      mysqls = mysqlService.list_active[1]
      if mysqls.empty?
        # No actives, look for proposals
        mysqls = mysqlService.proposals[1]
      end
      if mysqls.empty?
        @logger.info("Dashboard create_proposal: no mysql proposal found")
        base["attributes"]["nova_dashboard"]["sql_engine"] = ""
      else
        base["attributes"]["nova_dashboard"]["sql_instance"] = mysqls[0]
        base["attributes"]["nova_dashboard"]["sql_engine"] = "mysql"
      end
    rescue
      @logger.info("Nova dashboard create_proposal: no mysql found")
      base["attributes"]["nova_dashboard"]["sql_engine"] = ""
    end

    if base["attributes"]["nova_dashboard"]["sql_engine"] == ""
      begin
        pgsqlService = PostgresqlService.new(@logger)
        # Look for active roles
        pgsqls = pgsqlService.list_active[1]
        if pgsqls.empty?
          @logger.info("Dashboard create_proposal: no active postgresql proposal found")
          # No actives, look for proposals
          pgsqls = pgsqlService.proposals[1]
        end
        if pgsqls.empty?
          @logger.info("Dashboard create_proposal: no postgressql proposal found")
          base["attributes"]["nova_dashboard"]["sql_engine"] = ""
        else
          @logger.info("Dashboard create_proposal: postgresql instance #{pgsqls[0]}")
          base["attributes"]["nova_dashboard"]["sql_instance"] = pgsqls[0]
          base["attributes"]["nova_dashboard"]["sql_engine"] = "postgresql"
        end
      rescue
        @logger.info("Dashboard create_proposal: no postgresql found")
        base["attributes"]["nova_dashboard"]["sql_engine"] = ""
      end
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

    # Make sure the nodes have a link to the dashboard on them.
    all_nodes.each do |n|
      node = NodeObject.find_node_by_name(n)
      server_ip = node.get_network_by_type("admin")["address"]
      node.crowbar["crowbar"] = {} if node.crowbar["crowbar"].nil?
      node.crowbar["crowbar"]["links"] = {} if node.crowbar["crowbar"]["links"].nil?
      node.crowbar["crowbar"]["links"]["Nova Dashboard"] = "http://#{server_ip}/"
      node.save
    end
    @logger.debug("Nova_dashboard apply_role_pre_chef_call: leaving")
  end

end

