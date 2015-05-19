def upgrade ta, td, a, d
  a['policy_file_path'] = ta['policy_file_path']
  a['policy_file'] = ta['policy_file']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('policy_file_path')
  a.delete('policy_file')
  return a, d
end
