# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PrefetchRemoteAvatarJob do
  let(:actor) { create(:actor, :remote) }

  it 'runs the accessibility check (which enqueues a refresh when the URL is stale)' do
    processor = instance_double(ActorImageProcessor, avatar_url: '/icon.png')
    allow(ActorImageProcessor).to receive(:new).and_return(processor)

    described_class.perform_now(actor.id)

    expect(processor).to have_received(:avatar_url)
  end

  it 'skips actors whose avatar is already attached' do
    allow(Actor).to receive(:find_by).and_return(actor)
    allow(actor.avatar).to receive(:attached?).and_return(true)
    allow(actor).to receive(:avatar_url)

    described_class.perform_now(actor.id)

    expect(actor).not_to have_received(:avatar_url)
  end

  it 'ignores missing or local actors' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
