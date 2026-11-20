# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DeleteRemoteActorJob do
  let(:job) { described_class.new }
  let(:local_user) { create(:actor) }
  let(:remote) { create(:actor, :remote) }

  before { allow(job).to receive(:sleep) }

  it 'deletes the account together with its posts and relationships' do
    post = create(:activity_pub_object, :remote, :with_media, actor: remote)
    create(:reblog, actor: remote, object: create(:activity_pub_object, actor: local_user))
    create(:favourite, actor: local_user, object: post)
    create(:follow, :accepted, actor: local_user, target_actor: remote)
    create(:follow, :accepted, actor: remote, target_actor: local_user)
    HomeFeedEntry.create!(sort_id: post.id.to_s, object_id: post.id.to_s, actor_id: remote.id, created_at: Time.current)

    job.perform(remote.id)

    expect(Actor.exists?(remote.id)).to be false
    expect(ActivityPubObject.exists?(post.id)).to be false
    expect(MediaAttachment.where(actor_id: remote.id)).to be_empty
    expect(Reblog.where(actor_id: remote.id)).to be_empty
    expect(Favourite.where(object_id: post.id)).to be_empty
    expect(Follow.where(actor_id: remote.id).or(Follow.where(target_actor_id: remote.id))).to be_empty
    expect(HomeFeedEntry.where(object_id: post.id.to_s)).to be_empty
    expect(Actor.exists?(local_user.id)).to be true
  end

  it 'deletes many posts in small batches with pauses in between' do
    stub_const("#{described_class}::BATCH_SIZE", 2)
    create_list(:activity_pub_object, 5, :remote, actor: remote)

    job.perform(remote.id)

    expect(ActivityPubObject.where(actor_id: remote.id)).to be_empty
    expect(job).to have_received(:sleep).at_least(3).times
  end

  it 'never deletes a local account' do
    create(:activity_pub_object, actor: local_user)

    job.perform(local_user.id)

    expect(Actor.exists?(local_user.id)).to be true
    expect(ActivityPubObject.where(actor_id: local_user.id)).to exist
  end

  it 'does nothing when the account is already gone' do
    expect { job.perform(0) }.not_to raise_error
  end

  it 'processes one deletion per account at a time' do
    expect(described_class.new(remote.id).concurrency_key).to eq("DeleteRemoteActorJob/#{remote.id}")
    expect(described_class.concurrency_limit).to eq(1)
  end
end
