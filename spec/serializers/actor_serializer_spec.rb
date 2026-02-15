# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActorSerializer do
  let(:actor) { create(:actor, local: true, discoverable: true) }
  let(:serializer) { described_class.new(actor) }

  describe '#to_activitypub' do
    subject(:result) { serializer.to_activitypub }

    it 'includes indexable property' do
      expect(result).to have_key('indexable')
      expect(result['indexable']).to be(true)
    end

    it 'sets indexable to false when not discoverable' do
      actor.update!(discoverable: false)

      expect(result['indexable']).to be(false)
    end

    it 'includes alsoKnownAs as empty array' do
      expect(result).to have_key('alsoKnownAs')
      expect(result['alsoKnownAs']).to eq([])
    end

    it 'includes toot namespace in @context' do
      context = result['@context']
      context_objects = context.select { |c| c.is_a?(Hash) }
      toot_ns = context_objects.find { |c| c.key?('toot') }

      expect(toot_ns).to be_present
      expect(toot_ns['toot']).to eq('http://joinmastodon.org/ns#')
    end

    it 'includes indexable in @context namespace' do
      context = result['@context']
      context_objects = context.select { |c| c.is_a?(Hash) }
      indexable_ns = context_objects.find { |c| c.key?('indexable') }

      expect(indexable_ns).to be_present
      expect(indexable_ns['indexable']).to eq('toot:indexable')
    end

    it 'includes focalPoint definition in @context' do
      context = result['@context']
      context_objects = context.select { |c| c.is_a?(Hash) }
      fp_ns = context_objects.find { |c| c.key?('focalPoint') }

      expect(fp_ns).to be_present
    end

    it 'includes verified_at in attachment when present' do
      actor.update!(fields: [
        { name: 'Website', value: 'https://example.com', verified_at: '2024-01-01T00:00:00Z' }
      ].to_json)

      attachments = result['attachment']
      expect(attachments).to be_present
      expect(attachments.first['verified_at']).to eq('2024-01-01T00:00:00Z')
    end

    it 'omits verified_at in attachment when not present' do
      actor.update!(fields: [
        { name: 'Website', value: 'https://example.com' }
      ].to_json)

      attachments = result['attachment']
      expect(attachments).to be_present
      expect(attachments.first).not_to have_key('verified_at')
    end
  end
end
