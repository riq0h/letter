# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UnavailableServer, type: :model do
  subject { build(:unavailable_server) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:domain) }
    it { is_expected.to validate_inclusion_of(:reason).in_array(%w[gone timeout error]) }
    it { is_expected.to validate_presence_of(:first_error_at) }
    it { is_expected.to validate_presence_of(:last_error_at) }
    it { is_expected.to validate_uniqueness_of(:domain).case_insensitive }
  end

  describe 'indexes' do
    it 'has unique index on domain' do
      # 同じドメインで重複作成を試行
      create(:unavailable_server, domain: 'example.com')
      expect do
        create(:unavailable_server, domain: 'example.com')
      end.to raise_error(ActiveRecord::RecordInvalid, /Domain has already been taken/)
    end
  end

  describe '.unavailable?' do
    it 'returns true when domain is marked as unavailable' do
      create(:unavailable_server, domain: 'unavailable.com')
      expect(described_class.unavailable?('unavailable.com')).to be true
    end

    it 'returns false when domain is not marked as unavailable' do
      expect(described_class.unavailable?('available.com')).to be false
    end

    it 'normalizes domain names' do
      create(:unavailable_server, domain: 'example.com')
      expect(described_class.unavailable?('EXAMPLE.COM')).to be true
    end
  end

  describe '.record_gone_response' do
    it 'creates new record for new domain' do
      expect do
        described_class.record_gone_response('gone.example.com', '410 Gone')
      end.to change(described_class, :count).by(1)

      server = described_class.find_by(domain: 'gone.example.com')
      expect(server.reason).to eq('gone')
      expect(server.error_count).to eq(1)
      expect(server.last_error_message).to eq('410 Gone')
      expect(server.auto_detected).to be true
    end

    context 'when updating existing record' do
      let!(:server) do
        create(:unavailable_server,
               domain: 'existing.com',
               error_count: 1,
               first_error_at: 2.days.ago)
      end

      before do
        described_class.record_gone_response('existing.com', 'Second error')
        server.reload
      end

      it 'does not create new record' do
        expect do
          described_class.record_gone_response('existing.com', 'Third error')
        end.not_to change(described_class, :count)
      end

      it 'increments error count' do
        expect(server.error_count).to eq(2)
      end

      it 'updates last error message' do
        expect(server.last_error_message).to eq('Second error')
      end

      it 'updates last error timestamp' do
        expect(server.last_error_at).to be > 1.minute.ago
      end
    end
  end

  describe '.normalize_domain_name' do
    it 'converts to lowercase' do
      expect(described_class.normalize_domain_name('EXAMPLE.COM')).to eq('example.com')
    end

    it 'removes trailing dots' do
      expect(described_class.normalize_domain_name('example.com.')).to eq('example.com')
    end

    it 'strips whitespace' do
      expect(described_class.normalize_domain_name(' example.com ')).to eq('example.com')
    end
  end
end
