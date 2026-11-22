# frozen_string_literal: true

require 'rails_helper'

# 他サーバが投稿のURLを取りに来たときも、配信(Create/Update)と同じ内容を返す。
# Mastodonは引用できるかの判断や、引用リクエストを受けたときの確認にこれを使う
RSpec.describe 'Fetching a post as ActivityPub', type: :request do
  let(:owner) { create(:actor) }
  let(:headers) { { 'Accept' => 'application/activity+json' } }

  def fetch(post)
    get "/users/#{owner.username}/posts/#{post.id}", headers: headers
    ActiveSupport::JSON.decode(response.body)
  end

  it 'matches what was delivered to followers' do
    post = create(:activity_pub_object, actor: owner, content: '<p>こんにちは</p>')

    expect(fetch(post)).to eq(ActivityPubObjectSerializer.new(post).to_activitypub.as_json)
  end

  it 'tells who may quote the post' do
    post = create(:activity_pub_object, actor: owner, quote_policy: 'followers')

    expect(fetch(post)['interactionPolicy']).to eq('canQuote' => { 'automaticApproval' => [owner.followers_url] })
  end

  it 'shows what the post quotes and the approval for it' do
    quoted = create(:activity_pub_object, :remote, actor: create(:actor, :remote))
    post = create(:activity_pub_object, actor: owner, content: '<p>なるほど</p>')
    quote_post = QuotePost.create!(actor: owner, object: post, quoted_object: quoted, ap_id: "#{post.ap_id}#quote")
    quote_post.update!(quote_authorization_url: 'https://remote.example.com/approvals/1')

    body = fetch(post)

    expect(body).to include('quote' => quoted.ap_id, '_misskey_quote' => quoted.ap_id,
                            'quoteAuthorization' => 'https://remote.example.com/approvals/1')
    expect(body['content']).to include('quote-inline')
  end
end
