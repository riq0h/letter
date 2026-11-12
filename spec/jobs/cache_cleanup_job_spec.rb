# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CacheCleanupJob do
  def blob_with_key(key)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('x'), filename: 'e.png', content_type: 'image/png', key: key
    )
  end

  describe '#cleanup_orphaned_blobs' do
    it 'purges an old orphaned cache/ blob (e.g. left by a failed R2 upload)' do
      blob = blob_with_key('cache/orphan-old')
      blob.update_column(:created_at, 8.days.ago)

      described_class.new.send(:cleanup_orphaned_blobs)

      expect(ActiveStorage::Blob.exists?(blob.id)).to be false
    end

    it 'keeps a recent orphaned cache/ blob (may still be attaching)' do
      blob = blob_with_key('cache/orphan-recent')

      described_class.new.send(:cleanup_orphaned_blobs)

      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
    end

    it 'keeps an old but attached cache/ blob (successful emoji cache)' do
      emoji = create(:custom_emoji, :remote, image_url: 'https://remote.example.com/e.png')
      blob = blob_with_key('cache/attached')
      emoji.image.attach(blob)
      blob.update_column(:created_at, 8.days.ago)

      described_class.new.send(:cleanup_orphaned_blobs)

      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
    end

    it 'still purges old orphaned img/ blobs (legacy prefix)' do
      blob = blob_with_key('img/orphan-old')
      blob.update_column(:created_at, 8.days.ago)

      described_class.new.send(:cleanup_orphaned_blobs)

      expect(ActiveStorage::Blob.exists?(blob.id)).to be false
    end

    it 'does not touch other prefixes such as emoji/ or avatar/' do
      blob = blob_with_key('emoji/keep-me')
      blob.update_column(:created_at, 8.days.ago)

      described_class.new.send(:cleanup_orphaned_blobs)

      expect(ActiveStorage::Blob.exists?(blob.id)).to be true
    end
  end

  describe '#cleanup_cached_remote_media' do
    def cached_media_aged(days)
      media = create(:media_attachment, processing_status: 'cached')
      media.update_column(:updated_at, days.days.ago)
      media
    end

    it 'purges at most MAX_MEDIA_PURGE_PER_RUN expired cached media per run' do
      stub_const("#{described_class}::MAX_MEDIA_PURGE_PER_RUN", 2)
      media = Array.new(3) { cached_media_aged(15) }

      described_class.new.send(:cleanup_cached_remote_media)

      expect(MediaAttachment.where(id: media.map(&:id), processing_status: 'pending').count).to eq(2)
    end

    it 'keeps media within the default 14-day retention period' do
      recent = cached_media_aged(10)
      old = cached_media_aged(15)

      described_class.new.send(:cleanup_cached_remote_media)

      expect(recent.reload.processing_status).to eq('cached')
      expect(old.reload.processing_status).to eq('pending')
    end

    it 'follows the configured retention period' do
      InstanceConfig.set('media_cache_retention_days', '30')
      media = cached_media_aged(20)

      described_class.new.send(:cleanup_cached_remote_media)

      expect(media.reload.processing_status).to eq('cached')
    end
  end

  it 'is scheduled hourly as a recurring task in production' do
    recurring = YAML.load_file(Rails.root.join('config/recurring.yml'), aliases: true)

    expect(recurring.dig('production', 'cache_cleanup')).to include('class' => 'CacheCleanupJob', 'schedule' => 'every hour')
  end

  it 'never runs two cleanups at the same time' do
    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.concurrency_duration).to be >= 1.hour
  end
end
