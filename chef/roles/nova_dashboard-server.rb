name "nova_dashboard-server"
description "Nova_dashboard Server Role"
run_list(
         "recipe[nova_dashboard::api]",
         "recipe[nova_dashboard::monitor]"
)
default_attributes()
override_attributes()

