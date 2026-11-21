# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessQuoteRequestAnswerJob do
  let(:me) { create(:actor) }
  let(:quote_post) { quote! }
  let(:author) { create(:actor, :remote) }
  let(:quoted) { create(:activity_pub_object, :remote, actor: author) }
  let(:my_post) { create(:activity_pub_object, actor: me) }
  let(:authorization_uri) { "https://remote.example.com/users/#{author.username}/quote_authorizations/1" }

  def quote!
    QuotePost.create!(actor: me, object: my_post, quoted_object: quoted, ap_id: "#{my_post.ap_id}#quote")
  end

  def authorization(interacting: my_post.ap_id, target: quoted.ap_id)
    { 'id' => authorization_uri, 'type' => 'QuoteAuthorization', 'attributedTo' => author.ap_id,
      'interactingObject' => interacting, 'interactionTarget' => target }
  end

  it 'records a verified approval and redistributes the post so others can show the quote' do
    allow(ActivityPubHttpClient).to receive(:fetch_verified).with(authorization_uri, signing_actor: me)
                                                            .and_return(authorization)

    expect { described_class.perform_now(quote_post.id, 'Accept', author.id, authorization_uri) }
      .to change { Activity.where(activity_type: 'Update', object_ap_id: my_post.ap_id).count }.by(1)

    expect(quote_post.reload.quote_authorization_url).to eq(authorization_uri)
    note = my_post.reload.to_activitypub
    expect(note).to include('quote' => quoted.ap_id, 'quoteAuthorization' => authorization_uri)
  end

  it 'ignores an approval that does not cover this quote' do
    allow(ActivityPubHttpClient).to receive(:fetch_verified)
      .and_return(authorization(interacting: 'https://remote.example.com/statuses/other'))

    described_class.perform_now(quote_post.id, 'Accept', author.id, authorization_uri)

    expect(quote_post.reload).not_to be_approved
  end

  it 'ignores an approval hosted somewhere other than the author server' do
    allow(ActivityPubHttpClient).to receive(:fetch_verified)

    described_class.perform_now(quote_post.id, 'Accept', author.id, 'https://elsewhere.example/approvals/1')

    expect(ActivityPubHttpClient).not_to have_received(:fetch_verified)
    expect(quote_post.reload).not_to be_approved
  end

  it 'ignores answers from anyone but the quoted author' do
    described_class.perform_now(quote_post.id, 'Reject', create(:actor, :remote).id)

    expect(QuotePost.exists?(quote_post.id)).to be true
  end

  it 'stops quoting when the author rejects, keeping the post itself' do
    described_class.perform_now(quote_post.id, 'Reject', author.id)

    expect(QuotePost.exists?(quote_post.id)).to be false
    expect(my_post.reload.to_activitypub).not_to include('quote')
  end
end
