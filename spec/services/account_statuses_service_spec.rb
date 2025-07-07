# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountStatusesService do
  subject(:service) { described_class.new(account, params) }

  let(:account) { create(:actor) }
  let(:params) { {} }

  describe '#call' do
    context 'with pinned statuses only' do
      let(:params) { { pinned: 'true' } }
      let!(:pinned_status) { create(:activity_pub_object, :note, actor: account) }

      before do
        create(:pinned_status, actor: account, object: pinned_status)
        create(:activity_pub_object, :note, actor: account)
      end

      it 'returns only pinned statuses' do
        result = service.call
        expect(result).to eq([pinned_status])
      end
    end

    context 'with regular statuses' do
      let!(:older_status) { create(:activity_pub_object, :note, actor: account, published_at: 2.hours.ago) }
      let!(:newer_status) { create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago) }

      it 'returns statuses in reverse chronological order' do
        result = service.call
        expect(result).to eq([newer_status, older_status])
      end
    end

    context 'when excluding replies' do
      let(:params) { { exclude_replies: 'true' } }
      let!(:regular_status) { create(:activity_pub_object, :note, actor: account) }
      let!(:reply) { create(:activity_pub_object, :note, actor: account, in_reply_to_ap_id: 'https://example.com/status/1') }

      it 'excludes statuses with in_reply_to_ap_id' do
        result = service.call
        expect(result).not_to include(reply)
        expect(result).to include(regular_status)
      end
    end

    context 'when filtering only media' do
      let(:params) { { only_media: 'true' } }
      let!(:status_with_media) { create(:activity_pub_object, :note, actor: account) }

      before do
        create(:media_attachment, object: status_with_media, actor: account)
        create(:activity_pub_object, :note, actor: account)
      end

      it 'returns only statuses with media attachments' do
        result = service.call
        expect(result).to eq([status_with_media])
      end
    end

    context 'with max_id pagination' do
      let!(:older_status) { create(:activity_pub_object, :note, actor: account, published_at: 2.hours.ago) }
      let!(:newer_status) { create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago) }
      let(:params) { { max_id: newer_status.id } }

      it 'returns statuses before max_id' do
        result = service.call
        expect(result).to eq([older_status])
      end
    end

    context 'with since_id pagination' do
      let!(:older_status) { create(:activity_pub_object, :note, actor: account, published_at: 2.hours.ago) }
      let!(:newer_status) { create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago) }
      let(:params) { { since_id: older_status.id } }

      it 'returns statuses after since_id' do
        result = service.call
        expect(result).to eq([newer_status])
      end
    end

    context 'with pinned and regular statuses on first page' do
      let!(:pinned_status) { create(:activity_pub_object, :note, actor: account, published_at: 3.hours.ago) }
      let!(:older_regular) { create(:activity_pub_object, :note, actor: account, published_at: 2.hours.ago) }
      let!(:newer_regular) { create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago) }

      before do
        create(:pinned_status, actor: account, object: pinned_status)
      end

      it 'returns pinned statuses first, then regular statuses' do
        result = service.call
        expect(result.first).to eq(pinned_status)
        expect(result[1..]).to eq([newer_regular, older_regular])
      end

      it 'excludes pinned statuses from regular results' do
        result = service.call
        expect(result.count(pinned_status)).to eq(1)
      end
    end

    context 'with limit parameter' do
      let(:params) { { limit: 1 } }
      let!(:newer_status) { create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago) }

      before do
        create(:activity_pub_object, :note, actor: account, published_at: 2.hours.ago)
      end

      it 'limits the number of results' do
        result = service.call
        expect(result.size).to eq(1)
        expect(result).to eq([newer_status])
      end
    end
  end
end
