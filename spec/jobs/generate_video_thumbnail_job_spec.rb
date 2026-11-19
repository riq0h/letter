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
end
