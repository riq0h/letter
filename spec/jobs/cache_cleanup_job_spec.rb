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
end
