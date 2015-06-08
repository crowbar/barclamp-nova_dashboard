def upgrade ta, td, a, d
  a['use_keystone_v3'] = ta['use_keystone_v3']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('use_keystone_v3')
  return a, d
end
