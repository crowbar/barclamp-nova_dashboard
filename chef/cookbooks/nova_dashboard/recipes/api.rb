#
# Cookbook Name:: glance
# Recipe:: api
#
#

include_recipe "#{@cookbook_name}::common"

nova_dashboard_service "api"

node[:nova_dashboard][:monitor][:svcs] <<["nova_dashboard-api"]

