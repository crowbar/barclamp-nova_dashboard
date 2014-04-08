name "nova_dashboard-server_remove"
description "Deactivate Nova Dashboard Role services"
run_list(
  "recipe[nova_dashboard::deactivate_server]"
)
default_attributes()
override_attributes()
