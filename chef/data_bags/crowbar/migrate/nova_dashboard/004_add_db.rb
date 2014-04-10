def upgrade ta, td, a, d
  a['db'] = ta['db']

  # Old proposals had passwords created in the cookbook, but in the wrong
  # namespace for attributes. So no need to migrate them here. We use a class
  # variable to set the same password in the proposal and in the role, though
  unless defined?(@@nova_dashboard_db_password)
    service = ServiceObject.new "fake-logger"
    @@nova_dashboard_db_password = service.random_password
  end
  a['db']['password'] = @@nova_dashboard_db_password

  return a, d
end

def downgrade ta, td, a, d
  a.delete('db')
  return a, d
end
