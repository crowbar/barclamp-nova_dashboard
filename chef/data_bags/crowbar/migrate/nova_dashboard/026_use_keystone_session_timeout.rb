def upgrade ta, td, a, d
  keystone_instance = a['keystone_instance']
  proposal_obj = ProposalObject.find_proposal("keystone", keystone_instance)
  keystone_timeout = (proposal_obj["attributes"]["keystone"]["token_expiration"] || 14400)/60
  if proposal_obj && a['session_timeout'] > keystone_timeout
    a['session_timeout'] = keystone_timeout
  end
  return a, d
end

def downgrade ta, td, a, d
  return a, d
end
