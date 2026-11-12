# frozen_string_literal: true

require 'rails_helper'

# 識別子を検証する取得(他ホストへのリダイレクトや、他人のidを名乗る文書を拒否)
RSpec.describe ActivityPubHttpClient do
  let(:client) { described_class.new }

  def json_response(body, code: 200)
    instance_double(HTTParty::Response, code: code, success?: (200..299).cover?(code),
                                        body: body.to_json, headers: { 'content-type' => 'application/activity+json' })
  end

  def redirect_to(location)
    instance_double(HTTParty::Response, code: 302, success?: false, body: '', headers: { 'location' => location })
  end

  before { allow(client).to receive(:validate_url_for_ssrf!).and_return(true) }

  it 'returns a document whose id matches the requested URL' do
    allow(HTTParty).to receive(:get).with('https://origin.example/notes/1', anything)
                                    .and_return(json_response({ 'id' => 'https://origin.example/notes/1' }))

    expect(client.fetch_verified('https://origin.example/notes/1')).to include('id' => 'https://origin.example/notes/1')
  end

  it 'rejects a document claiming an id on another host' do
    allow(HTTParty).to receive(:get).with('https://attacker.example/x', anything)
                                    .and_return(json_response({ 'id' => 'https://victim.example/notes/1' }))
    # 名乗られたidを直接取りに行くと、本物は別の内容(別のid)を返す/存在しない
    allow(HTTParty).to receive(:get).with('https://victim.example/notes/1', anything)
                                    .and_return(json_response({}, code: 404))

    expect(client.fetch_verified('https://attacker.example/x')).to be_nil
  end

  it 'rejects a cross-host redirect to a document that claims the original id' do
    allow(HTTParty).to receive(:get).with('https://victim.example/redirect', anything)
                                    .and_return(redirect_to('https://attacker.example/doc'))
    allow(HTTParty).to receive(:get).with('https://attacker.example/doc', anything)
                                    .and_return(json_response({ 'id' => 'https://victim.example/redirect' }))

    expect(client.fetch_verified('https://victim.example/redirect')).to be_nil
  end

  it 'accepts a canonical id on the same server when that URL serves itself' do
    allow(HTTParty).to receive(:get).with('https://origin.example/@alice/1', anything)
                                    .and_return(json_response({ 'id' => 'https://origin.example/users/alice/statuses/1' }))
    allow(HTTParty).to receive(:get).with('https://origin.example/users/alice/statuses/1', anything)
                                    .and_return(json_response({ 'id' => 'https://origin.example/users/alice/statuses/1' }))

    expect(client.fetch_verified('https://origin.example/@alice/1'))
      .to include('id' => 'https://origin.example/users/alice/statuses/1')
  end
end
