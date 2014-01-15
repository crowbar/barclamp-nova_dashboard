def upgrade ta, td, a, d
  a['password_validator'] = ta['password_validator']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('password_validator')
  return a, d
end
