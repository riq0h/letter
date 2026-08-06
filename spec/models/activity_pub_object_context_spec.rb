# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPubObject do
  describe '#fep7888_context_uri' do
    let(:author) { create(:actor, local: true) }

    it 'returns own contexts URL for a local root post' do
      root = create(:activity_pub_object, :note, actor: author)

      expect(root.fep7888_context_uri).to end_with("/contexts/#{root.id}")
    end

    it 'returns the root contexts URL for a local reply in a local thread' do
      root = create(:activity_pub_object, :note, actor: author)
      reply = create(:activity_pub_object, :note, actor: author, in_reply_to_ap_id: root.ap_id)

      expect(reply.fep7888_context_uri).to end_with("/contexts/#{root.id}")
    end

    it 'inherits the remote root context when replying into a remote thread' do
      remote_root = create(:activity_pub_object, :note, actor: create(:actor, :remote), local: false,
                                                        ap_id: 'https://remote.example.com/notes/1',
                                                        raw_data: { context: 'https://remote.example.com/contexts/abc' }.to_json)
      reply = create(:activity_pub_object, :note, actor: author, in_reply_to_ap_id: remote_root.ap_id)

      expect(reply.fep7888_context_uri).to eq('https://remote.example.com/contexts/abc')
    end

    it 'returns nil when the remote root declares no usable context' do
      remote_root = create(:activity_pub_object, :note, actor: create(:actor, :remote), local: false,
                                                        ap_id: 'https://remote.example.com/notes/2', raw_data: '{}')
      reply = create(:activity_pub_object, :note, actor: author, in_reply_to_ap_id: remote_root.ap_id)

      expect(reply.fep7888_context_uri).to be_nil
    end

    it 'is included in the ActivityPub serialization' do
      root = create(:activity_pub_object, :note, actor: author)
      data = ActivityPubObjectSerializer.new(root).to_activitypub

      expect(data['context']).to end_with("/contexts/#{root.id}")
    end
  end
end
