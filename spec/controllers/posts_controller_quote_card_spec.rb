# frozen_string_literal: true

require 'rails_helper'

# 引用した投稿の中に、引用元の投稿を細い枠で表示する
RSpec.describe PostsController, type: :controller do
  render_views

  let(:owner) { create(:actor, username: 'owner', local: true) }
  let(:author) { create(:actor, :remote, username: 'kana', display_name: 'Kana') }
  let(:quoted) do
    create(:activity_pub_object, :remote, actor: author, content: '<p>返却ポストは二回に分けて回収しているそうです</p>')
  end
  let(:post_with_quote) { create(:activity_pub_object, actor: owner, content: 'これ気になってた') }

  def quote!(quoted_object = quoted, post = post_with_quote)
    QuotePost.create!(actor: post.actor, object: post, quoted_object: quoted_object, ap_id: "#{post.ap_id}#quote")
  end

  before { allow(LinkPreview).to receive(:fetch_or_create) }

  it 'shows the quoted post inside the post and labels it as a quote' do
    quote!

    get :show_html, params: { username: owner.username, id: post_with_quote.id }

    expect(response.body).to include('post-card-quote', '返却ポストは二回に分けて回収しているそうです',
                                     '@kana@remote.example.com', '引用</span>')
    expect(LinkPreview).not_to have_received(:fetch_or_create)
  end

  it 'hides a quoted post that is not public' do
    quoted.update!(visibility: 'private')
    quote!

    get :show_html, params: { username: owner.username, id: post_with_quote.id }

    expect(response.body).to include('引用元の投稿は公開範囲の設定で表示できません')
    expect(response.body).not_to include('返却ポストは二回に分けて回収しているそうです')
  end

  it 'shows a content warning before the quoted text' do
    quoted.update!(summary: '映画の結末に触れています')
    quote!

    get :show_html, params: { username: owner.username, id: post_with_quote.id }

    expect(response.body).to include('<details>', '映画の結末に触れています', '続きを読む')
  end

  it 'opens links in a new tab from the embedded view' do
    quote!

    get :embed, params: { username: owner.username, id: post_with_quote.id }

    expect(response.body).to include('post-card-quote', 'target="_blank"')
  end

  it 'links to a further quote instead of nesting it' do
    further = create(:activity_pub_object, :remote, actor: create(:actor, :remote, username: 'taku'))
    quote!(further, quoted)
    quote!

    get :show_html, params: { username: owner.username, id: post_with_quote.id }

    expect(response.body).to include('さらに別の投稿(@taku@remote.example.com)を引用しています')
    expect(response.body.scan('class="post-card-quote"').size).to eq(1)
  end
end
