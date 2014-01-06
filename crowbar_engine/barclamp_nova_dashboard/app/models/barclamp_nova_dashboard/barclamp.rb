# Copyright 2013, Dell, Inc. 
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

class BarclampNovaDashboard::Barclamp < Barclamp

  def initialize(thelogger)
    @bc_name = "nova_dashboard"
    @logger = thelogger
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

  def create_proposal(name)
    @logger.debug("Nova_dashboard create_proposal: entering")
    base = super(name)

    nodes = Node.all
    nodes.delete_if { |n| n.nil? or n.is_admin? }
    if nodes.size >= 1
      add_role_to_instance_and_node(nodes[0].name, base.name, "nova_dashboard-server")
    end

    base["attributes"]["nova_dashboard"]["database_instance"] = ""
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
      else
        base["attributes"]["nova_dashboard"]["database_instance"] = dbs[0]
      end
    rescue
      @logger.info("Nova dashboard create_proposal: no database found")
    end

    if base["attributes"]["nova_dashboard"]["database_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "database"))
    end

    hash["nova_dashboard"]["keystone_instance"] = ""
    begin
      keystoneService = Barclamp.find_by_name('keystone')
      keystones = keystoneService.active_proposals
      if keystones.empty?
        # No actives, look for proposals
        keystones = keystoneService.proposals
      end
      hash["nova_dashboard"]["keystone_instance"] = keystones[0].name unless keystones.empty?
    rescue
      @logger.info("Nova dashboard create_proposal: no keystone found")
    end

    if base["attributes"]["nova_dashboard"]["keystone_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "keystone"))
    end

    base["attributes"]["nova_dashboard"]["nova_instance"] = ""
    begin
      novaService = NovaService.new(@logger)
      novas = novaService.list_active[1]
      if novas.empty?
        # No actives, look for proposals
        novas = novaService.proposals[1]
      end
      base["attributes"]["nova_dashboard"]["nova_instance"] = novas[0] unless novas.empty?
    rescue
      @logger.info("Nova dashboard create_proposal: no nova found")
    end

    if base["attributes"]["nova_dashboard"]["nova_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "nova"))
    end

    base["attributes"][@bc_name]["git_instance"] = ""
    begin
      gitService = GitService.new(@logger)
      gits = gitService.list_active[1]
      if gits.empty?
        # No actives, look for proposals
        gits = gitService.proposals[1]
      end
      unless gits.empty?
        base["attributes"][@bc_name]["git_instance"] = gits[0]
      end
    rescue
      @logger.info("#{@bc_name} create_proposal: no git found")
    end

    @logger.debug("Nova_dashboard create_proposal: exiting")
    base
  end

  def validate_proposal_after_save proposal
    super
    if proposal["attributes"][@bc_name]["use_gitrepo"]
      gitService = GitService.new(@logger)
      gits = gitService.list_active[1].to_a
      if not gits.include?proposal["attributes"][@bc_name]["git_instance"]
        raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "git"))
      end
    end
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

