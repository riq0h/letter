# frozen_string_literal: true

require 'rails_helper'

# 投稿が名乗るlikes/sharesコレクション(件数のみ)
RSpec.describe 'Object likes and shares collections', type: :request do
  let(:author) { create(:actor) }
  let(:post_object) { create(:activity_pub_object, actor: author, favourites_count: 3, reblogs_count: 2) }
  let(:path) { URI(post_object.ap_id).path }

  # application/activity+json は parsed_body が解釈しない
  def json_body
    JSON.parse(response.body) # rubocop:disable Rails/ResponseParsedBody
  end

  it 'serves the likes collection the post advertises, with its count only' do
    get "#{path}/likes"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/activity+json')
    advertised = ActivityPubObjectSerializer.new(post_object).send(:likes_collection_data)
    expect(json_body).to include('id' => advertised['id'], 'type' => 'Collection', 'totalItems' => 3)
    expect(json_body).not_to have_key('items')
  end

  it 'serves the shares collection the post advertises' do
    get "#{path}/shares"

    expect(response).to have_http_status(:ok)
    advertised = ActivityPubObjectSerializer.new(post_object).send(:shares_collection_data)
    expect(json_body).to include('id' => advertised['id'], 'totalItems' => 2)
  end

  it 'does not reveal non-public posts' do
    private_post = create(:activity_pub_object, :private, actor: author)

    get "#{URI(private_post.ap_id).path}/likes"

    expect(response).to have_http_status(:not_found)
  end

  it 'does not serve a post under another user name' do
    other = create(:actor)

    get "/users/#{other.username}/posts/#{post_object.id}/likes"

    expect(response).to have_http_status(:not_found)
  end
end
