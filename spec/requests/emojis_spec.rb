# frozen_string_literal: true

require 'rails_helper'

# 投稿のtagに載せたEmojiのid(/emojis/:shortcode)が同じ絵文字を返す
RSpec.describe 'GET /emojis/:shortcode', type: :request do
  # application/activity+json は parsed_body が解釈しない
  def json_body
    JSON.parse(response.body) # rubocop:disable Rails/ResponseParsedBody
  end

  def create_local_emoji(shortcode, **attrs)
    emoji = build(:custom_emoji, :local, shortcode: shortcode, **attrs)
    emoji.image.attach(io: StringIO.new('dummy'), filename: "#{shortcode}.png", content_type: 'image/png')
    emoji.tap(&:save!)
  end

  it 'serves the same Emoji that a post advertises in its tags' do
    emoji = create_local_emoji('blobwave')
    post_object = create(:activity_pub_object, content: 'hi :blobwave:')
    tag = ActivityBuilders::TagBuilder.new(post_object).build.find { |t| t['type'] == 'Emoji' }

    get URI(tag['id']).path

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/activity+json')
    expect(json_body).to include(tag)
    expect(json_body['icon']['url']).to eq(emoji.image_url)
  end

  it 'prefers the local emoji over a remote one with the same name, as the tags do' do
    local = create_local_emoji('samename')
    create(:custom_emoji, :remote, shortcode: 'samename')

    get '/emojis/samename'

    expect(json_body['icon']['url']).to eq(local.image_url)
  end

  it 'serves a remote emoji when no local one exists, as the tags do' do
    remote = create(:custom_emoji, :remote, shortcode: 'remoteonly')

    get '/emojis/remoteonly'

    expect(response).to have_http_status(:ok)
    expect(json_body['icon']['url']).to eq(remote.image_url)
  end

  it 'returns 404 for a disabled or unknown emoji' do
    create_local_emoji('turnedoff', disabled: true)

    get '/emojis/turnedoff'
    expect(response).to have_http_status(:not_found)

    get '/emojis/nosuchemoji'
    expect(response).to have_http_status(:not_found)
  end
end
