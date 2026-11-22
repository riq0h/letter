# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessAccountMoveJob do
  let(:me) { create(:actor) }
  let(:old) { create(:actor, :remote) }
  let(:target_uri) { 'https://new.example/users/kana' }
  let(:target) do
    create(:actor, :remote, ap_id: target_uri, domain: 'new.example',
                            raw_data: { 'type' => 'Person', 'alsoKnownAs' => [old.ap_id] }.to_json)
  end
  let(:fetcher) { instance_double(ActorFetcher) }

  before do
    allow(ActorFetcher).to receive(:new).and_return(fetcher)
    allow(fetcher).to receive(:refresh) { |actor| actor }
  end

  def follow!(follower, followed)
    create(:follow, actor: follower, target_actor: followed, accepted: true)
  end

  it 'follows the new account and stops following the old one' do
    follow!(me, old)
    target

    described_class.perform_now(old.id, target_uri)

    expect(Follow.exists?(actor: me, target_actor: target)).to be true
    expect(Follow.exists?(actor: me, target_actor: old)).to be false
  end

  it 'fetches a new account it has not seen before' do
    follow!(me, old)
    allow(fetcher).to receive(:fetch_and_create).with(target_uri) { target }

    described_class.perform_now(old.id, target_uri)

    expect(Follow.exists?(actor: me, target_actor: target)).to be true
  end

  it 'ignores a move to an account that does not list the old one as an alias' do
    follow!(me, old)
    target.update!(raw_data: { 'type' => 'Person' }.to_json)

    described_class.perform_now(old.id, target_uri)

    expect(Follow.exists?(actor: me, target_actor: old)).to be true
    expect(Follow.exists?(actor: me, target_actor: target)).to be false
  end

  it 'carries blocks over and does not follow a blocked new account' do
    create(:block, actor: me, target_actor: old)
    target

    described_class.perform_now(old.id, target_uri)

    expect(me.blocking?(target)).to be true
    expect(Follow.exists?(actor: me, target_actor: target)).to be false
  end

  it 'carries mutes and list memberships over' do
    follow!(me, old)
    create(:mute, actor: me, target_actor: old)
    list = create(:list, actor: me)
    create(:list_membership, list: list, actor: old)
    target

    described_class.perform_now(old.id, target_uri)

    expect(me.muting?(target)).to be true
    expect(ListMembership.exists?(list: list, actor: target)).to be true
  end
end
