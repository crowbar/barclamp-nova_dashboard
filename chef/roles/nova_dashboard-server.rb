name "nova_dashboard-server"
description "Nova Dashboard Server Role"
run_list(
         "recipe[nova_dashboard::server]",
         "recipe[nova_dashboard::monitor]"
)
default_attributes()
override_attributes()

