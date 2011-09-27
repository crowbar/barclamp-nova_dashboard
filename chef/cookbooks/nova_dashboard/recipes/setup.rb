#
# Cookbook Name:: nova_dashboard
# Recipe:: setup
#

include_recipe "#{@cookbook_name}::common"

bash "tty linux setup" do
  cwd "/tmp"
  user "root"
  code <<-EOH
	mkdir -p /var/lib/nova_dashboard/
	curl #{node[:nova_dashboard][:tty_linux_image]} | tar xvz -C /tmp/
	touch /var/lib/nova_dashboard/tty_setup
  EOH
  not_if do File.exists?("/var/lib/nova_dashboard/tty_setup") end
end
