# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountStatusesService do
  subject(:service) { described_class.new(account, params) }

  let(:account) { create(:actor) }
  let(:params) { {} }

  describe 'integration tests' do
    describe 'with filters and pinned statuses' do
      it 'returns pinned first, then media statuses without replies' do
        pinned_status = create(:activity_pub_object, :note, actor: account, published_at: 5.hours.ago)
        regular_with_media = create(:activity_pub_object, :note, actor: account, published_at: 4.hours.ago)
        newest_with_media = create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago)

        create(:pinned_status, actor: account, object: pinned_status)
        create(:media_attachment, object: regular_with_media, actor: account)
        create(:media_attachment, object: newest_with_media, actor: account)
        create(:activity_pub_object, :note, actor: account, published_at: 3.hours.ago, in_reply_to_ap_id: 'https://example.com/1')

        service_with_filters = described_class.new(account, { exclude_replies: 'true', only_media: 'true' })
        result = service_with_filters.call
        expect(result).to eq([pinned_status, newest_with_media, regular_with_media])
      end

      it 'excludes pinned statuses on non-first page' do
        pinned_status = create(:activity_pub_object, :note, actor: account, published_at: 5.hours.ago)
        regular_with_media = create(:activity_pub_object, :note, actor: account, published_at: 4.hours.ago)
        newest_with_media = create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago)

        create(:pinned_status, actor: account, object: pinned_status)
        create(:media_attachment, object: regular_with_media, actor: account)
        create(:media_attachment, object: newest_with_media, actor: account)

        service_with_pagination = described_class.new(account, { exclude_replies: 'true', only_media: 'true', max_id: newest_with_media.id })
        result = service_with_pagination.call
        expect(result).to eq([regular_with_media])
        expect(result).not_to include(pinned_status)
      end
    end

    describe 'with pagination parameters' do
      it 'returns statuses after min_id without pinned' do
        pinned_status = create(:activity_pub_object, :note, actor: account, published_at: 5.hours.ago)
        regular_with_media = create(:activity_pub_object, :note, actor: account, published_at: 4.hours.ago)
        reply_with_media = create(:activity_pub_object, :note, actor: account, published_at: 3.hours.ago, in_reply_to_ap_id: 'https://example.com/1')
        regular_without_media = create(:activity_pub_object, :note, actor: account, published_at: 2.hours.ago)
        newest_with_media = create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago)

        create(:pinned_status, actor: account, object: pinned_status)

        service_with_min_id = described_class.new(account, { min_id: regular_with_media.id })
        result = service_with_min_id.call
        expect(result).to eq([newest_with_media, regular_without_media, reply_with_media])
      end

      it 'returns limited statuses after since_id without pinned' do
        pinned_status = create(:activity_pub_object, :note, actor: account, published_at: 5.hours.ago)
        reply_with_media = create(:activity_pub_object, :note, actor: account, published_at: 3.hours.ago, in_reply_to_ap_id: 'https://example.com/1')
        regular_without_media = create(:activity_pub_object, :note, actor: account, published_at: 2.hours.ago)
        newest_with_media = create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago)

        create(:pinned_status, actor: account, object: pinned_status)

        service_with_since_id = described_class.new(account, { since_id: reply_with_media.id, limit: 2 })
        result = service_with_since_id.call
        expect(result.size).to eq(2)
        expect(result).to eq([newest_with_media, regular_without_media])
      end
    end

    describe 'edge cases' do
      it 'returns empty array when account has no statuses' do
        result = service.call
        expect(result).to eq([])
      end

      it 'uses default limit of 20 with invalid limit parameter' do
        create_list(:activity_pub_object, 30, :note, actor: account)
        service_with_nil_limit = described_class.new(account, { limit: nil })
        result = service_with_nil_limit.call
        expect(result.size).to eq(20)
      end

      it 'returns empty array when all statuses are replies' do
        create_list(:activity_pub_object, 3, :note, actor: account, in_reply_to_ap_id: 'https://example.com/1')
        service_exclude_replies = described_class.new(account, { exclude_replies: 'true' })
        result = service_exclude_replies.call
        expect(result).to eq([])
      end

      it 'still shows pinned reply on first page when excluding replies' do
        pinned_reply = create(:activity_pub_object, :note, actor: account, in_reply_to_ap_id: 'https://example.com/1')
        regular_status = create(:activity_pub_object, :note, actor: account)
        create(:pinned_status, actor: account, object: pinned_reply)

        service_exclude_replies = described_class.new(account, { exclude_replies: 'true' })
        result = service_exclude_replies.call
        expect(result).to include(pinned_reply, regular_status)
      end
    end

    describe 'when verifying order' do
      it 'returns statuses in correct order' do
        Array.new(5) do |i|
          status = create(:activity_pub_object, :note, actor: account, published_at: (i + 1).hours.ago)
          create(:media_attachment, object: status, actor: account)
          status
        end

        result = service.call

        # 正しい順序（新しい順）を published_at で確認
        expect(result.map(&:published_at)).to eq(result.map(&:published_at).sort.reverse)
        expect(result.size).to eq(5)
      end
    end
  end
end
