# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountIdentifier do
  describe '.parse' do
    it 'parses @username@domain format correctly' do
      identifier = described_class.parse('@alice@example.com')
      expect(identifier.username).to eq('alice')
      expect(identifier.domain).to eq('example.com')
    end

    it 'parses username@domain format correctly' do
      identifier = described_class.parse('alice@example.com')
      expect(identifier.username).to eq('alice')
      expect(identifier.domain).to eq('example.com')
    end

    it 'parses acct:username@domain format correctly' do
      identifier = described_class.parse('acct:alice@example.com')
      expect(identifier.username).to eq('alice')
      expect(identifier.domain).to eq('example.com')
    end

    it 'sets domain to nil for local username only' do
      identifier = described_class.parse('alice')
      expect(identifier.username).to eq('alice')
      expect(identifier.domain).to be_nil
    end

    it 'returns nil for empty string' do
      expect(described_class.parse('')).to be_nil
    end

    it 'returns nil for nil input' do
      expect(described_class.parse(nil)).to be_nil
    end
  end

  describe '.parse_acct_uri' do
    it 'parses acct:username@domain format correctly' do
      identifier = described_class.parse_acct_uri('acct:alice@example.com')
      expect(identifier.username).to eq('alice')
      expect(identifier.domain).to eq('example.com')
    end

    it 'returns nil for format without @' do
      expect(described_class.parse_acct_uri('alice')).to be_nil
    end

    it 'returns nil for multiple @ symbols' do
      expect(described_class.parse_acct_uri('alice@bob@example.com')).to be_nil
    end
  end

  describe '.from_mention' do
    it 'creates from mention format' do
      identifier = described_class.from_mention('alice@example.com')
      expect(identifier.username).to eq('alice')
      expect(identifier.domain).to eq('example.com')
    end

    it 'creates from local mention without @' do
      identifier = described_class.from_mention('alice')
      expect(identifier.username).to eq('alice')
      expect(identifier.domain).to be_nil
    end

    it 'returns nil for empty string' do
      expect(described_class.from_mention('')).to be_nil
    end
  end

  describe '#local?' do
    it 'returns true when domain is absent' do
      identifier = described_class.new('alice')
      expect(identifier).to be_local
    end

    it 'returns false when domain is present' do
      identifier = described_class.new('alice', 'example.com')
      expect(identifier).not_to be_local
    end
  end

  describe '#remote?' do
    it 'returns true when domain is present' do
      identifier = described_class.new('alice', 'example.com')
      expect(identifier).to be_remote
    end

    it 'returns false when domain is absent' do
      identifier = described_class.new('alice')
      expect(identifier).not_to be_remote
    end
  end

  describe '#to_webfinger_uri' do
    it 'returns WebFinger URI format' do
      identifier = described_class.new('alice', 'example.com')
      expect(identifier.to_webfinger_uri).to eq('acct:alice@example.com')
    end

    it 'returns nil for local user' do
      identifier = described_class.new('alice')
      expect(identifier.to_webfinger_uri).to be_nil
    end
  end

  describe '#to_s' do
    it 'returns username@domain for remote user' do
      identifier = described_class.new('alice', 'example.com')
      expect(identifier.to_s).to eq('alice@example.com')
    end

    it 'returns username only for local user' do
      identifier = described_class.new('alice')
      expect(identifier.to_s).to eq('alice')
    end
  end

  describe '#full_acct' do
    it 'returns account name with @' do
      identifier = described_class.new('alice', 'example.com')
      expect(identifier.full_acct).to eq('@alice@example.com')
    end

    it 'returns with @ even for local user' do
      identifier = described_class.new('alice')
      expect(identifier.full_acct).to eq('@alice')
    end
  end

  describe '#==' do
    it 'returns true for same username and domain' do
      identifier1 = described_class.new('alice', 'example.com')
      identifier2 = described_class.new('alice', 'example.com')
      expect(identifier1).to eq(identifier2)
    end

    it 'returns false for different username' do
      identifier1 = described_class.new('alice', 'example.com')
      identifier2 = described_class.new('bob', 'example.com')
      expect(identifier1).not_to eq(identifier2)
    end

    it 'returns false for different domain' do
      identifier1 = described_class.new('alice', 'example.com')
      identifier2 = described_class.new('alice', 'other.com')
      expect(identifier1).not_to eq(identifier2)
    end

    it 'returns false for objects of other classes' do
      identifier = described_class.new('alice', 'example.com')
      expect(identifier).not_to eq('alice@example.com')
    end
  end

  describe '.account_query?' do
    it 'returns true for @username@domain format' do
      expect(described_class.account_query?('@alice@example.com')).to be true
    end

    it 'returns true for username@domain format' do
      expect(described_class.account_query?('alice@example.com')).to be true
    end

    it 'returns true for @username only' do
      expect(described_class.account_query?('@alice')).to be true
    end

    it 'returns true for domain format' do
      expect(described_class.account_query?('example.com')).to be true
    end

    it 'returns false for regular text' do
      expect(described_class.account_query?('hello world')).to be false
    end

    it 'returns false for empty string' do
      expect(described_class.account_query?('')).to be false
    end
  end

  describe '.domain_query?' do
    it 'returns true for domain.com format' do
      expect(described_class.domain_query?('example.com')).to be true
    end

    it 'returns false when containing @' do
      expect(described_class.domain_query?('alice@example.com')).to be false
    end

    it 'returns false when not domain format' do
      expect(described_class.domain_query?('example')).to be false
    end
  end

  describe 'immutability' do
    it 'is immutable' do
      identifier = described_class.new('alice', 'example.com')
      expect(identifier).to be_frozen
    end
  end

  describe 'normalization' do
    it 'strips whitespace from username and domain' do
      identifier = described_class.new(' alice ', ' example.com ')
      expect(identifier.username).to eq('alice')
      expect(identifier.domain).to eq('example.com')
    end

    it 'normalizes domain to lowercase' do
      identifier = described_class.new('alice', 'EXAMPLE.COM')
      expect(identifier.domain).to eq('example.com')
    end
  end
end
