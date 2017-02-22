unless node['roles'].include?('nova_dashboard-server')
  node["nova_dashboard"]["services"]["server"].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node.delete("nova_dashboard")
  node.save
end
