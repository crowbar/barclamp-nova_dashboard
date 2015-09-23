def upgrade(ta, td, a, d)
  unless a.has_key? "multi_domain_support"
    a["multi_domain_support"] = ta["multi_domain_support"]
  end
  return a, d
end

def downgrade(ta, td, a, d)
  unless ta.has_key? "multi_domain_support"
    a.delete("multi_domain_support")
  end
  return a, d
end
