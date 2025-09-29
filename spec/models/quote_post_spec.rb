# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuotePost, type: :model do
  let(:actor) { create(:actor) }
  let(:quoted_object) { create(:activity_pub_object) }
  let(:quote_object) { create(:activity_pub_object) }

  describe 'associations' do
    it { is_expected.to belong_to(:actor) }
    it { is_expected.to belong_to(:object).class_name('ActivityPubObject') }
    it { is_expected.to belong_to(:quoted_object).class_name('ActivityPubObject') }
    it { is_expected.to have_one(:quote_authorization).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:quote_post) }

    it { is_expected.to validate_presence_of(:ap_id) }
    it { is_expected.to validate_uniqueness_of(:ap_id) }
  end

  describe 'FEP-044f support' do
    let(:quote_post) do
      create(:quote_post,
             actor: actor,
             object: quote_object,
             quoted_object: quoted_object)
    end

    describe 'interaction policy' do
      it 'sets default interaction policy on save' do
        expect(quote_post.interaction_policy).to eq({
                                                      'canQuote' => {
                                                        'automaticApproval' => ['https://www.w3.org/ns/activitystreams#Public']
                                                      }
                                                    })
      end
    end

    describe 'quote authorization' do
      it 'creates quote authorization after creation' do
        expect(quote_post.quote_authorization).to be_present
        expect(quote_post.quote_authorization_url).to be_present
      end

      it 'creates valid authorization data' do
        auth = quote_post.quote_authorization
        expect(auth.ap_id).to eq(quote_post.quote_authorization_url)
        expect(auth.actor).to eq(quoted_object.actor)
        expect(auth.interacting_object_id).to eq(quote_post.ap_id)
        expect(auth.interaction_target_id).to eq(quoted_object.ap_id)
      end
    end

    describe '#to_activitypub' do
      let(:json) { quote_post.to_activitypub }

      it 'includes FEP-044f context' do
        context = json['@context']
        expect(context).to be_an(Array)
        expect(context[0]).to eq('https://www.w3.org/ns/activitystreams')

        extensions = context[1]
        expect(extensions['quote']['@id']).to eq('https://w3id.org/fep/044f#quote')
        expect(extensions['quoteAuthorization']['@id']).to eq('https://w3id.org/fep/044f#quoteAuthorization')
      end

      it 'includes all quote properties for compatibility' do
        expect(json['quote']).to eq(quoted_object.ap_id)
        expect(json['quoteUrl']).to eq(quoted_object.ap_id)
        expect(json['quoteUri']).to eq(quoted_object.ap_id)
        expect(json['_misskey_quote']).to eq(quoted_object.ap_id)
      end

      it 'includes quote authorization URL' do
        expect(json['quoteAuthorization']).to eq(quote_post.quote_authorization_url)
      end

      it 'includes interaction policy' do
        expect(json['interactionPolicy']).to eq(quote_post.interaction_policy)
      end

      it 'has correct type' do
        expect(json['type']).to eq('Note')
      end
    end
  end
end
