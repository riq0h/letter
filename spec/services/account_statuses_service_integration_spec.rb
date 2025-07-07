# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountStatusesService, 'integration tests' do
  subject(:service) { described_class.new(account, params) }

  let(:account) { create(:actor) }
  let(:params) { {} }

  describe 'complex scenarios' do
    context 'with all parameters combined' do
      let!(:pinned_status) { create(:activity_pub_object, :note, actor: account, published_at: 5.hours.ago) }
      let!(:regular_with_media) { create(:activity_pub_object, :note, actor: account, published_at: 4.hours.ago) }
      let!(:reply_with_media) { create(:activity_pub_object, :note, actor: account, published_at: 3.hours.ago, in_reply_to_ap_id: 'https://example.com/1') }
      let!(:regular_without_media) { create(:activity_pub_object, :note, actor: account, published_at: 2.hours.ago) }
      let!(:newest_with_media) { create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago) }

      before do
        create(:pinned_status, actor: account, object: pinned_status)
        create(:media_attachment, object: regular_with_media, actor: account)
        create(:media_attachment, object: reply_with_media, actor: account)
        create(:media_attachment, object: newest_with_media, actor: account)
      end

      context 'excluding replies and only media on first page' do
        let(:params) { { exclude_replies: 'true', only_media: 'true' } }

        it 'returns pinned first, then media statuses without replies' do
          result = service.call
          expect(result).to eq([pinned_status, newest_with_media, regular_with_media])
        end
      end

      context 'with pagination and filters' do
        let(:params) { { exclude_replies: 'true', only_media: 'true', max_id: newest_with_media.id } }

        it 'excludes pinned statuses on non-first page' do
          result = service.call
          expect(result).to eq([regular_with_media])
          expect(result).not_to include(pinned_status)
        end
      end

      context 'with min_id parameter' do
        let(:params) { { min_id: regular_with_media.id } }

        it 'returns statuses after min_id without pinned' do
          result = service.call
          # min_idがあるので最初のページではない → ピン留めなし
          expect(result).to eq([newest_with_media, regular_without_media, reply_with_media])
        end
      end

      context 'with since_id and limit' do
        let(:params) { { since_id: reply_with_media.id, limit: 2 } }

        it 'returns limited statuses after since_id without pinned' do
          result = service.call
          expect(result.size).to eq(2)
          # since_idがあるので最初のページではない → ピン留めなし
          expect(result).to eq([newest_with_media, regular_without_media])
        end
      end
    end

    context 'edge cases' do
      context 'when account has no statuses' do
        it 'returns empty array' do
          result = service.call
          expect(result).to eq([])
        end
      end

      context 'with invalid limit parameter' do
        let(:params) { { limit: nil } }
        let!(:statuses) { create_list(:activity_pub_object, 30, :note, actor: account) }

        it 'uses default limit of 20' do
          result = service.call
          expect(result.size).to eq(20)
        end
      end

      context 'when all statuses are replies' do
        let(:params) { { exclude_replies: 'true' } }

        before do
          create_list(:activity_pub_object, 3, :note, actor: account, in_reply_to_ap_id: 'https://example.com/1')
        end

        it 'returns empty array' do
          result = service.call
          expect(result).to eq([])
        end
      end

      context 'when pinned status is also a reply' do
        let(:params) { { exclude_replies: 'true' } }
        let!(:pinned_reply) { create(:activity_pub_object, :note, actor: account, in_reply_to_ap_id: 'https://example.com/1') }
        let!(:regular_status) { create(:activity_pub_object, :note, actor: account) }

        before do
          create(:pinned_status, actor: account, object: pinned_reply)
        end

        it 'still shows pinned reply on first page' do
          result = service.call
          expect(result).to include(pinned_reply, regular_status)
        end
      end
    end

    context 'order and includes verification' do
      let!(:statuses) do
        5.times.map do |i|
          status = create(:activity_pub_object, :note, actor: account, published_at: (i + 1).hours.ago)
          create(:media_attachment, object: status, actor: account)
          status
        end
      end

      it 'returns statuses in correct order' do
        result = service.call
        
        # デバッグ情報
        puts "Expected order (newest first):"
        statuses.reverse.each { |s| puts "ID: #{s.id}, published_at: #{s.published_at}" }
        puts "\nActual result:"
        result.each { |s| puts "ID: #{s.id}, published_at: #{s.published_at}" }
        
        # 正しい順序（新しい順）を published_at で確認
        expect(result.map(&:published_at)).to eq(result.map(&:published_at).sort.reverse)
        expect(result.size).to eq(5)
      end
    end
  end
end