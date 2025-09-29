# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuoteAuthorization, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:actor) }
    it { is_expected.to belong_to(:quote_post) }
  end

  describe 'validations' do
    subject { build(:quote_authorization) }

    it { is_expected.to validate_presence_of(:ap_id) }
    it { is_expected.to validate_uniqueness_of(:ap_id) }
    it { is_expected.to validate_presence_of(:interacting_object_id) }
    it { is_expected.to validate_presence_of(:interaction_target_id) }
  end

  describe '#to_activitypub' do
    let(:actor) { create(:actor) }
    let(:quote_post) { create(:quote_post) }
    let(:quote_authorization) do
      create(:quote_authorization,
             actor: actor,
             quote_post: quote_post,
             ap_id: 'https://example.com/quote_auth/123',
             interacting_object_id: 'https://example.com/posts/456',
             interaction_target_id: 'https://example.com/posts/789')
    end

    let(:json) { quote_authorization.to_activitypub }

    it 'includes correct context' do
      context = json['@context']
      expect(context).to be_an(Array)
      expect(context[0]).to eq('https://www.w3.org/ns/activitystreams')

      extensions = context[1]
      expect(extensions['QuoteAuthorization']).to eq('https://w3id.org/fep/044f#QuoteAuthorization')
      expect(extensions['interactingObject']['@id']).to eq('gts:interactingObject')
      expect(extensions['interactionTarget']['@id']).to eq('gts:interactionTarget')
    end

    it 'includes correct type and id' do
      expect(json['type']).to eq('QuoteAuthorization')
      expect(json['id']).to eq('https://example.com/quote_auth/123')
    end

    it 'includes attribution and object references' do
      expect(json['attributedTo']).to eq(actor.ap_id)
      expect(json['interactingObject']).to eq('https://example.com/posts/456')
      expect(json['interactionTarget']).to eq('https://example.com/posts/789')
    end
  end

  describe '.validate_quote' do
    let(:actor) { create(:actor) }
    let(:quoted_object) { create(:activity_pub_object, actor: actor) }
    let(:quote_post) { create(:quote_post, quoted_object: quoted_object) }
    let(:quote_authorization) { quote_post.quote_authorization }

    context 'with valid authorization' do
      it 'returns true for valid quote' do
        result = described_class.validate_quote(
          quote_post.ap_id,
          quoted_object.ap_id,
          quote_authorization.ap_id
        )
        expect(result).to be true
      end
    end

    context 'with invalid authorization' do
      it 'returns false for non-existent authorization' do
        result = described_class.validate_quote(
          quote_post.ap_id,
          quoted_object.ap_id,
          'https://invalid.com/auth/123'
        )
        expect(result).to be false
      end

      it 'returns false for blank authorization URL' do
        result = described_class.validate_quote(
          quote_post.ap_id,
          quoted_object.ap_id,
          ''
        )
        expect(result).to be false
      end
    end
  end
end
