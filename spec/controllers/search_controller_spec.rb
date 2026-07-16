# frozen_string_literal: true

require 'rails_helper'

# フロント検索の無限スクロール(オフセットページ)が実際に投稿を描画することを検証する。
# 過去にSearchQueryの素のオブジェクト配列をpost_timeline(timeline_item形式を期待)へ
# 渡していたため、2ページ目以降が空(投稿0件)になる退行があった。
RSpec.describe SearchController, type: :controller do
  render_views

  let(:actor) { create(:actor, local: true) }

  before do
    35.times do |i|
      create(:activity_pub_object, :note, actor: actor, local: true, visibility: 'public',
                                          content: "hello.jp テスト投稿 #{i}",
                                          content_plaintext: "hello.jp テスト投稿 #{i}")
    end
  end

  it 'renders posts on the first page with a chain frame to the next page' do
    get :index, params: { q: 'hello.jp' }

    expect(response).to have_http_status(:ok)
    expect(response.body.scan('<article').size).to eq(30)
    expect(response.body).to include('id="load_more_30"')
  end

  it 'renders the remaining posts on the offset page (2ページ目が空にならない)' do
    get :index, params: { q: 'hello.jp', offset: 30 }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="load_more_30"')
    expect(response.body.scan('<article').size).to eq(5)
    # 35件で尽きるので次ページのframeは無い
    expect(response.body).not_to include('id="load_more_60"')
  end
end
