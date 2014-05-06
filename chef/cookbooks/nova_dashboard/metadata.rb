# -*- encoding : utf-8 -*-
maintainer       "User Unknown"
maintainer_email "Unknown@Sample.com"
license          "Apache 2.0"
description      "Installs/Configures Nova Dashboard"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.me'))
version          "0.0"

depends "apache2"
depends "database"
depends "nagios"
depends "git"
depends "memcached"
depends "keystone"
depends "crowbar-pacemaker"
depends "utils"
