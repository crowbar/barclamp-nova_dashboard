def upgrade ta, td, a, d
  a['site_branding_link'] = ta['site_branding_link']

  return a, d
end

def downgrade ta, td, a, d
  a.delete('site_branding_link')
  return a, d
end
