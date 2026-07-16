# frozen_string_literal: true

require 'rails_helper'
require 'vips'

# アバター再添付の抑制: 取得元URLが不変なら再ダウンロード/再添付しない。
# 毎回再添付するとblobキー(=配信URL)が変わり、クライアントがキャッシュ済みの
# 旧URLが404になって「アバター欠落→リロードで直る」現象を生むため。
RSpec.describe ActorCreationService do
  let(:service) { described_class.new }
  let(:actor) { create(:actor, :remote) }
  let(:jpeg_bytes) { Vips::Image.black(20, 20).write_to_buffer('.jpg') }
  let(:url) { 'https://remote.example.com/avatar/a.jpg' }

  def fake_response(body)
    resp = instance_double(Net::HTTPOK, body: body)
    allow(resp).to receive(:[]).with('content-type').and_return('image/jpeg')
    resp
  end

  before do
    allow(service).to receive(:fetch_image_response).and_return(fake_response(jpeg_bytes))
  end

  it 'records the source URL in blob metadata on attach' do
    service.send(:attach_remote_image, actor, :avatar, url)

    expect(actor.avatar).to be_attached
    expect(actor.avatar.blob.metadata['source_url']).to eq(url)
  end

  it 'skips re-download and keeps the same blob when the source URL is unchanged' do
    service.send(:attach_remote_image, actor, :avatar, url)
    first_blob_id = actor.reload.avatar.blob.id

    service.send(:attach_remote_image, actor, :avatar, url)

    expect(actor.reload.avatar.blob.id).to eq(first_blob_id)
    expect(service).to have_received(:fetch_image_response).once
  end

  it 're-attaches with a new blob when the source URL changed (avatar actually updated)' do
    service.send(:attach_remote_image, actor, :avatar, url)
    first_blob_id = actor.reload.avatar.blob.id

    service.send(:attach_remote_image, actor, :avatar, 'https://remote.example.com/avatar/b.jpg')

    expect(actor.reload.avatar.blob.id).not_to eq(first_blob_id)
    expect(service).to have_received(:fetch_image_response).twice
  end

  it 'headers get the same treatment' do
    service.send(:attach_remote_image, actor, :header, url)
    first_blob_id = actor.reload.header.blob.id

    service.send(:attach_remote_image, actor, :header, url)

    expect(actor.reload.header.blob.id).to eq(first_blob_id)
  end
end
