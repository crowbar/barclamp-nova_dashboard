case node["platform"]
when "suse"
  default["nova_dashboard"]["services"] = {
    "server" => ["apache2"]
  }
end
