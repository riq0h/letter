# frozen_string_literal: true

require 'rails_helper'

# Mastodon 4.6互換: GET /api/v1/accounts/:id/statuses の exclude_direct フラグ。
# letterはこのエンドポイントで元々directを常時除外しているため実質no-opだが、
# フラグを受理してエラーにならないこと・除外が保たれることを固定する
RSpec.describe Api::V1::AccountsController, type: :controller do
  let(:account) { create(:actor, local: true) }
  let!(:public_post) { create(:activity_pub_object, :note, actor: account, visibility: 'public') }
  let!(:direct_post) { create(:activity_pub_object, :direct, actor: account) }

  it 'never serves direct posts on this endpoint (existing behavior)' do
    get :statuses, params: { id: account.id }

    ids = response.parsed_body.pluck('id')
    expect(ids).to include(public_post.id.to_s)
    expect(ids).not_to include(direct_post.id.to_s)
  end

  it 'accepts exclude_direct=true and keeps direct posts excluded' do
    get :statuses, params: { id: account.id, exclude_direct: 'true' }

    expect(response).to have_http_status(:ok)
    ids = response.parsed_body.pluck('id')
    expect(ids).to include(public_post.id.to_s)
    expect(ids).not_to include(direct_post.id.to_s)
  end
end
