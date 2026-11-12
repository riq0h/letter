# frozen_string_literal: true

require 'rails_helper'

# アカウント(表示名・自己紹介・フィールド)絵文字の一括先読み
RSpec.describe StatusSerializationHelper do
  let(:harness) do
    Class.new do
      include StatusSerializationHelper
      include TextLinkingHelper

      def current_user = nil
      def params = {}
    end.new
  end

  let(:own_domain) { 'own.example' }
  let(:account) { create(:actor, :remote, domain: own_domain, display_name: 'alice :blobcat:') }

  def attach_image(emoji)
    emoji.image.attach(io: StringIO.new('img'), filename: 'e.png', content_type: 'image/png')
    emoji
  end

  it "selects the account's own-domain emoji even when other servers have the same shortcode" do
    create(:custom_emoji, :remote, shortcode: 'blobcat', domain: 'other.example')
    own = create(:custom_emoji, :remote, shortcode: 'blobcat', domain: own_domain)

    harness.send(:preload_account_emojis, [account])

    expect(harness.send(:account_emojis, account).first[:url]).to eq(own.url)
  end

  it 'falls back to another server when neither the account domain nor local has it' do
    create(:custom_emoji, :remote, shortcode: 'blobcat', domain: 'other.example')

    harness.send(:preload_account_emojis, [account])

    expect(harness.send(:account_emojis, account).pluck(:shortcode)).to eq(['blobcat'])
  end

  it 'preloads cached images so serializing does not query per emoji' do
    attach_image(create(:custom_emoji, :remote, shortcode: 'blobcat', domain: own_domain))
    harness.send(:preload_account_emojis, [account])

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      harness.send(:account_emojis, account)
    end

    expect(queries).to eq(0)
  end
end
