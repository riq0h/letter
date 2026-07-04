# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RefreshRemoteActorJob do
  it 'refreshes an existing remote actor via ActorFetcher' do
    actor = create(:actor, :remote)
    fetcher = instance_double(ActorFetcher)
    allow(ActorFetcher).to receive(:new).and_return(fetcher)

    expect(fetcher).to receive(:refresh).with(actor)

    described_class.perform_now(actor.id)
  end

  it 'does nothing for a local actor' do
    local = create(:actor, local: true)
    allow(ActorFetcher).to receive(:new)

    described_class.perform_now(local.id)

    expect(ActorFetcher).not_to have_received(:new)
  end

  it 'does nothing when the actor is missing' do
    allow(ActorFetcher).to receive(:new)

    described_class.perform_now(-1)

    expect(ActorFetcher).not_to have_received(:new)
  end
end
