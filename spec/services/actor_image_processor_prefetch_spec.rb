# frozen_string_literal: true

require 'rails_helper'

# 受信時のアバター先回り確認(初回表示だけフォールバックになる問題への対処)
RSpec.describe ActorImageProcessor do
  include ActiveJob::TestHelper

  describe '#enqueue_avatar_prefetch' do
    let(:actor) { create(:actor, :remote) }
    let(:processor) { described_class.new(actor) }

    before do
      allow(actor).to receive(:extract_remote_image_url).with('icon')
                                                        .and_return('https://remote.example.com/a.png')
    end

    it 'enqueues a prefetch job for a remote actor without an attached avatar' do
      expect { processor.enqueue_avatar_prefetch }.to have_enqueued_job(PrefetchRemoteAvatarJob).with(actor.id)
    end

    it 'only enqueues once within 24 hours' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

      processor.enqueue_avatar_prefetch
      expect { processor.enqueue_avatar_prefetch }.not_to have_enqueued_job(PrefetchRemoteAvatarJob)
    end

    it 'does not enqueue when the avatar is already attached' do
      allow(actor.avatar).to receive(:attached?).and_return(true)

      expect { processor.enqueue_avatar_prefetch }.not_to have_enqueued_job(PrefetchRemoteAvatarJob)
    end

    it 'does not enqueue when the actor has no icon' do
      allow(actor).to receive(:extract_remote_image_url).with('icon').and_return(nil)

      expect { processor.enqueue_avatar_prefetch }.not_to have_enqueued_job(PrefetchRemoteAvatarJob)
    end

    it 'does not enqueue for local actors' do
      local = create(:actor, local: true)

      expect { described_class.new(local).enqueue_avatar_prefetch }.not_to have_enqueued_job(PrefetchRemoteAvatarJob)
    end
  end
end
