define :nova_dashboard_service do

  nova_dashboard_name="nova_dashboard-#{params[:name]}"

  service nova_dashboard_name do
    if (platform?("ubuntu") && node.platform_version.to_f >= 10.04)
      restart_command "restart #{nova_dashboard_name}"
      stop_command "stop #{nova_dashboard_name}"
      start_command "start #{nova_dashboard_name}"
      status_command "status #{nova_dashboard_name} | cut -d' ' -f2 | cut -d'/' -f1 | grep start"
    end
    supports :status => true, :restart => true
    action [:enable, :start]
    subscribes :restart, resources(:template => node[:nova_dashboard][:config_file])
  end

end
