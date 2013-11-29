def upgrade ta, td, a, d
  a['session_timeout'] = ta['session_timeout']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('session_timeout')
  return a, d
end
