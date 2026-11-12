# frozen_string_literal: true

require 'rails_helper'

# Mastodon 5.0互換のホームTLフィルタ(exclude_reblogs / exclude_replies / exclude_quotes)
RSpec.describe TimelineQuery do
  let(:user) { create(:actor, local: true) }
  let(:friend) { create(:actor, local: true) }
  let!(:plain) { create(:activity_pub_object, :note, actor: friend) }
  let!(:reply) { create(:activity_pub_object, :note, actor: friend, in_reply_to_ap_id: plain.ap_id) }
  let!(:quoting) { create(:activity_pub_object, :note, actor: friend) }
  let!(:reblog) { Reblog.create!(actor: friend, object: create(:activity_pub_object, :note, actor: create(:actor, local: true))) }

  before do
    create(:follow, actor: user, target_actor: friend)
    create(:quote_post, object: quoting, quoted_object: plain, actor: friend)
  end

  def home(params = {})
    described_class.new(user, params.merge(limit: 40)).build_home_timeline
  end

  it 'returns everything without filters' do
    result = home
    expect(result.grep(Reblog)).to include(reblog)
    expect(result.grep(ActivityPubObject)).to include(plain, reply, quoting)
  end

  it 'drops boosts with exclude_reblogs' do
    expect(home(exclude_reblogs: 'true').grep(Reblog)).to be_empty
  end

  it 'drops replies with exclude_replies' do
    expect(home(exclude_replies: 'true')).not_to include(reply)
  end

  it 'drops quote posts with exclude_quotes' do
    result = home(exclude_quotes: 'true')
    expect(result).not_to include(quoting)
    expect(result).to include(plain)
  end
end
