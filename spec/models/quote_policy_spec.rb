# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuotePolicy do
  let(:me) { create(:actor) }
  let(:stranger) { create(:actor, :remote) }

  def follow!(follower, followed)
    create(:follow, actor: follower, target_actor: followed, accepted: true)
  end

  describe '.setting_for' do
    it 'keeps a valid setting for public and unlisted posts' do
      expect(described_class.setting_for('public', 'followers')).to eq('followers')
      expect(described_class.setting_for('unlisted', 'nobody')).to eq('nobody')
    end

    it 'falls back to anyone for a missing or unknown setting' do
      expect(described_class.setting_for('public', nil)).to eq('public')
      expect(described_class.setting_for('public', 'everyone')).to eq('public')
    end

    it 'allows nobody else to quote followers-only posts and DMs' do
      expect(described_class.setting_for('private', 'public')).to eq('nobody')
      expect(described_class.setting_for('direct', 'public')).to eq('nobody')
    end
  end

  describe 'posts on this server' do
    def my_post(visibility: 'public', quote_policy: nil)
      create(:activity_pub_object, actor: me, visibility: visibility, quote_policy: quote_policy)
    end

    it 'lets anyone quote a post without a setting' do
      policy = described_class.new(my_post)

      expect(policy.automatic).to eq(['public'])
      expect(policy.manual).to eq([])
      expect(policy.for(stranger)).to eq('automatic')
    end

    it 'lets only followers quote a followers setting' do
      policy = described_class.new(my_post(quote_policy: 'followers'))
      follower = create(:actor, :remote)
      follow!(follower, me)

      expect(policy.automatic).to eq(['followers'])
      expect(policy.for(follower)).to eq('automatic')
      expect(policy.for(stranger)).to eq('denied')
    end

    it 'lets nobody but the author quote a nobody setting' do
      policy = described_class.new(my_post(quote_policy: 'nobody'))

      expect(policy.automatic).to eq([])
      expect(policy.for(stranger)).to eq('denied')
      expect(policy.for(me)).to eq('automatic')
    end

    it 'lets nobody else quote followers-only posts, whatever the setting says' do
      policy = described_class.new(my_post(visibility: 'private', quote_policy: 'public'))

      expect(policy.for(stranger)).to eq('denied')
      expect(policy.for(me)).to eq('automatic')
    end

    it 'does not let even the author quote a DM' do
      expect(described_class.new(my_post(visibility: 'direct')).for(me)).to eq('denied')
    end

    it 'denies accounts and servers the author blocked' do
      post = my_post
      Block.create!(actor: me, target_actor: stranger)
      blocked_server_user = create(:actor, :remote, domain: 'blocked.example')
      DomainBlock.create!(actor: me, domain: 'blocked.example')

      expect(described_class.new(post).for(stranger)).to eq('denied')
      expect(described_class.new(post).for(blocked_server_user)).to eq('denied')
    end

    it 'is unknown for a viewer who is not logged in' do
      expect(described_class.new(my_post).for(nil)).to eq('unknown')
    end

    it 'publishes the setting as interactionPolicy' do
      public_policy = described_class.new(my_post).to_interaction_policy
      followers_policy = described_class.new(my_post(quote_policy: 'followers')).to_interaction_policy
      nobody_policy = described_class.new(my_post(visibility: 'private')).to_interaction_policy

      expect(public_policy).to eq('canQuote' => { 'automaticApproval' => [described_class::PUBLIC_COLLECTION] })
      expect(followers_policy).to eq('canQuote' => { 'automaticApproval' => [me.followers_url] })
      expect(nobody_policy).to eq('canQuote' => { 'automaticApproval' => [me.ap_id] })
    end
  end

  describe 'posts from other servers' do
    let(:author) { create(:actor, :remote) }

    def remote_post(can_quote, visibility: 'public')
      raw = can_quote ? { 'interactionPolicy' => { 'canQuote' => can_quote } } : { 'type' => 'Note' }
      create(:activity_pub_object, :remote, actor: author, visibility: visibility, raw_data: raw.to_json)
    end

    it 'treats public posts from servers without quote settings as quotable by anyone' do
      policy = described_class.new(remote_post(nil))

      expect(policy).not_to be_declared
      expect(policy.automatic).to eq(['public'])
      expect(policy.for(me)).to eq('automatic')
    end

    it 'follows a policy that lets anyone quote' do
      policy = described_class.new(remote_post({ 'automaticApproval' => [described_class::PUBLIC_COLLECTION] }))

      expect(policy).to be_declared
      expect(policy.for(me)).to eq('automatic')
    end

    it 'lets us quote a followers policy only while we follow the author' do
      post = remote_post({ 'automaticApproval' => [author.followers_url] })

      expect(described_class.new(post).automatic).to eq(['followers'])
      expect(described_class.new(post).for(me)).to eq('denied')

      follow!(me, author)
      expect(described_class.new(post).for(me)).to eq('automatic')
    end

    it 'reports quotes the author reviews by hand as manual' do
      policy = described_class.new(remote_post({ 'automaticApproval' => [author.ap_id],
                                                 'manualApproval' => [described_class::PUBLIC_COLLECTION] }))

      expect(policy.automatic).to eq([])
      expect(policy.manual).to eq(['public'])
      expect(policy.for(me)).to eq('manual')
    end

    it 'reads the older GoToSocial keys' do
      expect(described_class.new(remote_post({ 'always' => ['as:Public'] })).for(me)).to eq('automatic')
    end

    it 'is unknown when the policy lists accounts it cannot classify' do
      policy = described_class.new(remote_post({ 'automaticApproval' => ['https://elsewhere.example/users/someone'] }))

      expect(policy.automatic).to eq(['unsupported_policy'])
      expect(policy.for(me)).to eq('unknown')
      expect(policy.allows?(me)).to be true
    end

    it 'denies quoting when only the author may quote' do
      policy = described_class.new(remote_post({ 'automaticApproval' => [author.ap_id] }))

      expect(policy.for(me)).to eq('denied')
      expect(policy.allows?(me)).to be false
    end

    it 'denies followers-only posts even from servers without quote settings' do
      expect(described_class.new(remote_post(nil, visibility: 'private')).for(me)).to eq('denied')
    end
  end
end
