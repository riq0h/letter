# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe GenerateVideoThumbnailJob do
  let(:job) { described_class.new }
  let(:frame) do
    red = Vips::Image.black(16, 16).new_from_image([220, 30, 30])
    blue = Vips::Image.black(16, 16).new_from_image([30, 30, 220])
    red.join(blue, :horizontal).copy(interpretation: :srgb).write_to_buffer('.jpg')
  end

  before { allow(job).to receive(:generate_thumbnail).and_return(StringIO.new(frame)) }

  # blurhashが無い動画は、作ったサムネイルから計算する
  it 'attaches the thumbnail and computes the missing blurhash from it' do
    media = create(:media_attachment, :video)

    job.perform(media.id)

    media.reload
    expect(media.thumbnail).to be_attached
    expect(media.blurhash).not_to eq(BlurhashGenerator::PLACEHOLDER)
    expect(Blurhash.components(media.blurhash)).to eq([4, 4])
  end

  it 'keeps the blurhash the origin server sent' do
    media = create(:media_attachment, :video, blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj')

    job.perform(media.id)

    expect(media.reload.blurhash).to eq('LEHV6nWB2yk8pyo0adR*.7kCMdnj')
  end

  # 同じ動画のジョブが同時に動くと、サムネイルが2つ付いてしまう
  it 'runs one job at a time for the same video' do
    expect(described_class.new(42).concurrency_key).to eq('GenerateVideoThumbnailJob/42')
    expect(described_class.concurrency_limit).to eq(1)
  end

  it 'does nothing when the video already has a thumbnail' do
    media = create(:media_attachment, :video)
    job.perform(media.id)

    expect { job.perform(media.id) }.not_to(change { ActiveStorage::Attachment.where(record: media).count })
    expect(job).to have_received(:generate_thumbnail).once
  end
end
