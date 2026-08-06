# frozen_string_literal: true

require 'rails_helper'

# FEP-7888: 会話contextコレクションの配信
RSpec.describe ContextsController, type: :controller do
  let(:author) { create(:actor, local: true) }
  let(:root) { create(:activity_pub_object, :note, actor: author, visibility: 'public') }

  it 'serves the thread members as an OrderedCollection attributed to the root author' do
    reply = create(:activity_pub_object, :note, actor: author, visibility: 'public',
                                                in_reply_to_ap_id: root.ap_id)
    nested = create(:activity_pub_object, :note, actor: author, visibility: 'public',
                                                 in_reply_to_ap_id: reply.ap_id)

    get :show, params: { id: root.id }

    expect(response).to have_http_status(:ok)
    # activity+json応答はparsed_bodyでJSON解釈されないため明示的にparseする
    body = JSON.parse(response.body) # rubocop:disable Rails/ResponseParsedBody
    expect(body['type']).to eq('OrderedCollection')
    expect(body['attributedTo']).to eq(author.ap_id)
    expect(body['orderedItems']).to eq([root.ap_id, reply.ap_id, nested.ap_id])
  end

  it 'excludes non-public replies from the collection' do
    create(:activity_pub_object, :direct, actor: author, in_reply_to_ap_id: root.ap_id)

    get :show, params: { id: root.id }

    expect(JSON.parse(response.body)['orderedItems']).to eq([root.ap_id]) # rubocop:disable Rails/ResponseParsedBody
  end

  it 'returns 404 for a remote root' do
    remote = create(:activity_pub_object, :note, actor: create(:actor, :remote), local: false,
                                                 visibility: 'public', ap_id: 'https://remote.example.com/notes/1')

    get :show, params: { id: remote.id }

    expect(response).to have_http_status(:not_found)
  end
end
