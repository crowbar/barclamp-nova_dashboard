def upgrade ta, td, a, d
  a['external_monitoring'] = {}
  return a, d
end

def downgrade ta, td, a, d
  a.delete('external_monitoring')
  return a, d
end

