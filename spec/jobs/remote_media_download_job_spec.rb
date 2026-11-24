# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe RemoteMediaDownloadJob do
  let(:job) { described_class.new }
  let(:image_data) do
    red = Vips::Image.black(16, 16).new_from_image([220, 30, 30])
    blue = Vips::Image.black(16, 16).new_from_image([30, 30, 220])
    red.join(blue, :horizontal).copy(interpretation: :srgb).write_to_buffer('.png')
  end

  before do
    allow(job).to receive(:validate_url_for_ssrf!).and_return(true)
    allow(job).to receive(:download_to_tempfile) do
      Tempfile.new(['remote_media', '.bin'], binmode: true).tap do |file|
        file.write(image_data)
        file.rewind
      end
    end
  end

  # 相手サーバがblurhashを送ってこなかった画像は、取り込んだ画像から計算する
  it 'computes the blurhash of an image the origin server sent without one' do
    media = create(:media_attachment)
    expect(media.blurhash).to eq(BlurhashGenerator::PLACEHOLDER)

    job.perform(media.id)

    media.reload
    expect(media.file).to be_attached
    expect(media.blurhash).not_to eq(BlurhashGenerator::PLACEHOLDER)
    expect(Blurhash.components(media.blurhash)).to eq([4, 4])
  end

  it 'keeps the blurhash the origin server sent' do
    media = create(:media_attachment, blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj')

    job.perform(media.id)

    expect(media.reload.blurhash).to eq('LEHV6nWB2yk8pyo0adR*.7kCMdnj')
  end

  it 'does not download a file of a type the server cannot handle' do
    media = create(:media_attachment, content_type: 'application/octet-stream',
                                      remote_url: 'https://remote.example/files/3f2a9c', file_name: '3f2a9c')

    job.perform(media.id)

    expect(job).not_to have_received(:download_to_tempfile)
    expect(media.reload.file).not_to be_attached
  end
end
