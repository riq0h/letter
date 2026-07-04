# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActorImageProcessor do
  include ActiveJob::TestHelper

  describe '#avatar_url on-demand refresh' do
    let(:actor) { create(:actor, :remote) }
    let(:processor) { described_class.new(actor) }

    before do
      allow(actor).to receive(:extract_remote_image_url).with('icon')
                                                        .and_return('https://remote.example.com/a.png')
      allow(processor).to receive(:remote_image_accessible_cached?).and_return(false)
    end

    it 'returns the fallback icon and enqueues a refresh when the remote avatar is inaccessible' do
      url = nil
      expect { url = processor.avatar_url }.to have_enqueued_job(RefreshRemoteActorJob).with(actor.id)
      expect(url).to end_with('/icon.png')
    end

    it 'does not enqueue when the remote avatar is accessible' do
      allow(processor).to receive(:remote_image_accessible_cached?).and_return(true)

      expect { processor.avatar_url }.not_to have_enqueued_job(RefreshRemoteActorJob)
    end

    it 'only enqueues once within the cooldown window' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

      processor.avatar_url
      expect { processor.avatar_url }.not_to have_enqueued_job(RefreshRemoteActorJob)
    end

    it 'does not enqueue for local actors' do
      local = create(:actor, local: true)
      local_processor = described_class.new(local)
      allow(local).to receive(:extract_remote_image_url).with('icon')
                                                        .and_return('https://remote.example.com/a.png')
      allow(local_processor).to receive(:remote_image_accessible_cached?).and_return(false)

      expect { local_processor.avatar_url }.not_to have_enqueued_job(RefreshRemoteActorJob)
    end
  end
end
