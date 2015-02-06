def upgrade ta, td, a, d
  unless a.has_key? 'site_theme'
    a['site_theme'] = ta['site_theme']
  end
  return a, d
end

def downgrade ta, td, a, d
  unless ta.has_key? 'site_theme'
    a.delete('site_theme')
  end
  return a, d
end
