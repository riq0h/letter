# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trending tags', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:actor) }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Test App', redirect_uri: 'https://localhost', confidential: false)
  end
  let(:access_token) do
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: application,
                                    scopes: 'read', expires_in: 2.hours)
  end
  let(:auth) { { 'Authorization' => "Bearer #{access_token.token}" } }

  def tag_post(tag, actor: create(:actor, :remote), at: Time.current)
    travel_to(at) { create(:object_tag, tag: tag, object: create(:activity_pub_object, :remote, actor: actor)) }
  end

  def trending_names
    get '/api/v1/trends', params: { limit: 10 }, headers: auth
    response.parsed_body.pluck('name')
  end

  it 'ranks tags by how many accounts on other servers used them this week' do
    many = create(:tag, name: 'many')
    few = create(:tag, name: 'few')
    3.times { tag_post(many) }
    bot = create(:actor, :remote)
    5.times { tag_post(few, actor: bot) }

    expect(trending_names).to eq(%w[many few])
  end

  it 'leaves out tags used only before this week' do
    tag_post(create(:tag, name: 'old'), at: 8.days.ago)
    tag_post(create(:tag, name: 'new'))

    expect(trending_names).to eq(%w[new])
  end

  it 'leaves out tags used only on this server' do
    local = create(:tag, name: 'mine')
    create(:object_tag, tag: local, object: create(:activity_pub_object, actor: user))

    expect(trending_names).to be_empty
  end
end
