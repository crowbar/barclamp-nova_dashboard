def upgrade ta, td, a, d
  unless a.has_key? 'help_url'
    a['help_url'] = ta['help_url']
  end
  return a, d
end

def downgrade ta, td, a, d
  unless ta.has_key? 'help_url'
    a.delete('help_url')
  end
  return a, d
end
