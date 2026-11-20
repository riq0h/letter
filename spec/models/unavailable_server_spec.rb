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
    it 'stops delivery once failures have lasted for the failure period' do
      create(:unavailable_server, domain: 'down.example', first_error_at: 15.days.ago, last_error_at: 1.hour.ago)

      expect(described_class.unavailable?('down.example')).to be true
    end

    it 'keeps delivering while failures are more recent than the failure period' do
      create(:unavailable_server, domain: 'flaky.example', first_error_at: 3.days.ago, last_error_at: 1.hour.ago)

      expect(described_class.unavailable?('flaky.example')).to be false
    end

    it 'returns false when the domain has no failures' do
      expect(described_class.unavailable?('available.example')).to be false
    end

    it 'normalizes domain names' do
      create(:unavailable_server, domain: 'down.example', first_error_at: 15.days.ago, last_error_at: 1.hour.ago)

      expect(described_class.unavailable?('DOWN.EXAMPLE')).to be true
    end
  end

  describe '.delivery_failure?' do
    it 'counts no response, server errors and retryable client errors' do
      expect(described_class.delivery_failure?({ success: false, error: 'Timeout: execution expired' })).to be true
      expect(described_class.delivery_failure?({ success: false, code: 503 })).to be true
      expect(described_class.delivery_failure?({ success: false, code: 429 })).to be true
    end

    # 410は「その宛先(アカウント)は無い」という応答で、サーバ自体は動いている
    it 'does not count gone or other client errors' do
      expect(described_class.delivery_failure?({ success: false, code: 410 })).to be false
      expect(described_class.delivery_failure?({ success: false, code: 404 })).to be false
      expect(described_class.delivery_failure?({ success: true, code: 202 })).to be false
    end
  end

  describe '.record_failure' do
    it 'starts a failure record for a new domain' do
      server = described_class.record_failure('down.example', 'Timeout: execution expired')

      expect(server).to have_attributes(reason: 'timeout', error_count: 1, last_error_message: 'Timeout: execution expired')
      expect(server.first_error_at).to eq(server.last_error_at)
    end

    it 'extends an existing record without moving its first failure' do
      first = 3.days.ago
      create(:unavailable_server, domain: 'down.example', first_error_at: first, last_error_at: 2.days.ago, error_count: 1)

      server = described_class.record_failure('down.example', '503 - unavailable')

      expect(server.error_count).to eq(2)
      expect(server.first_error_at).to be_within(1.second).of(first)
      expect(server.last_error_at).to be > 1.minute.ago
    end
  end

  describe '.record_success' do
    it 'removes the failure record so that delivery resumes' do
      create(:unavailable_server, domain: 'down.example', first_error_at: 15.days.ago, last_error_at: 1.hour.ago)

      described_class.record_success('down.example')

      expect(described_class.exists?(domain: 'down.example')).to be false
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
