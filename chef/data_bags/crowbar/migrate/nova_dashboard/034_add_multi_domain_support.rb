def upgrade ta, td, a, d
  a['multi_domain_support'] = ta['multi_domain_support']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('multi_domain_support')
  return a, d
end
