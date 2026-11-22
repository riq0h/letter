# frozen_string_literal: true

require 'rails_helper'

# 他サーバの投稿を引用したときは作者のサーバに承認を求める(FEP-044f / Mastodon 4.5以降)
RSpec.describe QuotePost do
  let(:me) { create(:actor) }
  let(:author) { create(:actor, :remote) }
  let(:quoted) { create(:activity_pub_object, :remote, actor: author) }
  let(:my_post) { create(:activity_pub_object, actor: me) }
  let(:authorization_uri) { "https://remote.example.com/users/#{author.username}/quote_authorizations/1" }

  def quote!
    QuotePost.create!(actor: me, object: my_post, quoted_object: quoted, ap_id: "#{my_post.ap_id}#quote")
  end

  it 'asks the author server for approval instead of issuing an authorization itself' do
    quote_post = nil
    expect { quote_post = quote! }.to have_enqueued_job(SendQuoteRequestJob)

    expect(quote_post.quote_authorization).to be_nil
    expect(quote_post).not_to be_approved
  end

  it 'authorizes quotes of our own posts without asking anyone' do
    own_post = create(:activity_pub_object, actor: me)
    own = nil
    expect do
      own = described_class.create!(actor: me, object: my_post, quoted_object: own_post, ap_id: "#{my_post.ap_id}#quote")
    end.not_to have_enqueued_job(SendQuoteRequestJob)

    expect(own).to be_approved
  end

  it 'finds the quote by the id of the request it sent' do
    quote_post = quote!

    expect(described_class.from_quote_request_ap_id(quote_post.quote_request_ap_id)).to eq(quote_post)
    expect(described_class.from_quote_request_ap_id("https://other.example/users/x#quote_requests/#{quote_post.id}")).to be_nil
  end

  describe '#awaiting_approval?' do
    let(:policy_quoted) do
      create(:activity_pub_object, :remote, actor: author,
                                            raw_data: { 'interactionPolicy' => { 'canQuote' => {} } }.to_json)
    end

    it 'is true while a server that supports approvals has not answered yet' do
      quote_post = described_class.create!(actor: me, object: my_post, quoted_object: policy_quoted, ap_id: "#{my_post.ap_id}#quote")

      expect(quote_post).to be_awaiting_approval
    end

    it 'is false for servers without quote approvals, which never answer' do
      expect(quote!).not_to be_awaiting_approval
    end

    it 'is false once approved' do
      quote_post = described_class.create!(actor: me, object: my_post, quoted_object: policy_quoted, ap_id: "#{my_post.ap_id}#quote")
      quote_post.update!(quote_authorization_url: authorization_uri)

      expect(quote_post).not_to be_awaiting_approval
    end
  end
end
