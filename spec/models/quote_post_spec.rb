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

  describe '.record!' do
    it 'returns the existing record for a quote already recorded' do
      first = described_class.record!(quote_object, quoted_object)

      expect(described_class.record!(quote_object, quoted_object)).to eq(first)
      expect(described_class.count).to eq(1)
    end

    it 'uses the record that another process made at the same moment' do
      # 記録が無いのを確かめたあと、自分が記録する前に別の処理が同じ引用を記録する
      allow(described_class).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs) if described_class.none?
        original.call(*args, **kwargs)
      end

      quote_post = described_class.record!(quote_object, quoted_object)

      expect(quote_post).to be_persisted
      expect(described_class.where(object: quote_object, quoted_object: quoted_object).count).to eq(1)
    end

    it 'still raises when the quote cannot be recorded for another reason' do
      quote_object.update_column(:visibility, 'unknown')

      expect { described_class.record!(quote_object, quoted_object) }.to raise_error(ActiveRecord::RecordInvalid)
    end
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
        expect(auth.interacting_object_id).to eq(quote_post.object.ap_id)
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
