# frozen_string_literal: true

require 'rails_helper'

# トップページ(投稿カード)とプロフィール(共通カード)でも、引用元を枠で表示する
RSpec.describe 'Quote cards on timelines', type: :request do
  let(:owner) { create(:actor, username: 'owner', local: true) }
  let(:author) { create(:actor, :remote, username: 'kana') }

  before do
    allow(LinkPreview).to receive(:fetch_or_create)
    post = create(:activity_pub_object, actor: owner, content: 'これ気になってた')
    quoted = create(:activity_pub_object, :remote, actor: author, content: '<p>返却ポストの回収は二回</p>')
    QuotePost.create!(actor: owner, object: post, quoted_object: quoted, ap_id: "#{post.ap_id}#quote")
  end

  it 'shows the quoted post on the top page' do
    get root_path

    expect(response.body).to include('post-card-quote', '返却ポストの回収は二回')
  end

  it 'shows the quoted post inside a boosted quote post' do
    boosted = create(:activity_pub_object, :remote, actor: author, content: '<p>こちらも引用です</p>')
    target = create(:activity_pub_object, :remote, actor: create(:actor, :remote, username: 'taku'),
                                                   content: '<p>引用された側の投稿</p>')
    QuotePost.create!(actor: author, object: boosted, quoted_object: target, ap_id: "#{boosted.ap_id}#quote")
    Reblog.create!(actor: owner, object: boosted)

    get root_path

    expect(response.body).to include('引用された側の投稿')
  end

  it 'shows the quoted post on the profile page' do
    get profile_path(owner.username)

    expect(response.body).to include('post-card-quote', '返却ポストの回収は二回')
  end
end
