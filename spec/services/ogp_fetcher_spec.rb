# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OgpFetcher do
  it 'shortens a title that is too long to keep as a preview' do
    html = %(<html><head><meta property="og:title" content="#{'title ' * 80}"></head></html>)

    data = described_class.new.send(:parse_ogp, html, 'https://news.example/article')

    expect(data[:title].length).to eq(255)
    expect(LinkPreview.new(data)).to be_valid
  end
end
