# Copyright 2012, Dell, Inc. 
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

  def proposal_dependencies(new_config)
    answer = []
    hash = new_config.config_hash
    if hash["sql_engine"] == "mysql"
      answer << { "barclamp" => "mysql", "inst" => hash["mysql_instance"] }
    end
    answer << { "barclamp" => "keystone", "inst" => hash["keystone_instance"] }
    answer
  end

  def create_proposal
    @logger.debug("Nova_dashboard create_proposal: entering")
    base = super

    nodes = Node.all
    nodes.delete_if { |n| n.nil? or n.is_admin? }
    if nodes.size >= 1
      add_role_to_instance_and_node(nodes[0].name, base.name, "nova_dashboard-server")
    end

    hash = base.config_hash
    hash["mysql_instance"] = ""
    begin
      mysqlService = Barclamp.find_by_name('mysql')
      mysqls = mysqlService.active_proposals
      if mysqls.empty?
        # No actives, look for proposals
        mysqls = mysqlService.proposals
      end
      unless mysqls.empty?
        hash["mysql_instance"] = mysqls[0].name
      end
      hash["sql_engine"] = "mysql"
    rescue
      @logger.info("Nova dashboard create_proposal: no mysql found")
      hash["sql_engine"] = "mysql"
    end

    hash["keystone_instance"] = ""
    begin
      keystoneService = Barclamp.find_by_name('keystone')
      keystones = keystoneService.active_proposals
      if keystones.empty?
        # No actives, look for proposals
        keystones = keystoneService.proposals
      end
      hash["keystone_instance"] = keystones[0].name unless keystones.empty?
    rescue
      @logger.info("Nova dashboard create_proposal: no keystone found")
    end

    base.config_hash = hash

    @logger.debug("Nova_dashboard create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_config, new_config, all_nodes)
    @logger.debug("Nova_dashboard apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    # Make sure the nodes have a link to the dashboard on them.
    all_nodes.each do |node|
      server_ip = node.address.addr
      chash = new_config.get_node_config_hash(node)
      chash["crowbar"] = {} if chash["crowbar"].nil?
      chash["crowbar"]["links"] = {} if chash["crowbar"]["links"].nil?
      chash["crowbar"]["links"]["Nova Dashboard"] = "http://#{server_ip}/"
      new_config.set_node_config_hash(node, chash)
    end
    @logger.debug("Nova_dashboard apply_role_pre_chef_call: leaving")
  end

end

