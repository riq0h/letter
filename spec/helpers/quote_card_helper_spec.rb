# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuoteCardHelper, type: :helper do
  let(:author) { create(:actor, :remote) }

  def quote(post, quoted)
    QuotePost.create!(actor: post.actor, object: post, quoted_object: quoted, ap_id: "#{post.ap_id}#quote")
  end

  describe '#content_without_quote_fallback' do
    it 'drops the "RE: link" fallback of a quote post, since the quote is shown as a card' do
      post = create(:activity_pub_object, :remote, actor: author,
                                                   content: '<p>本文</p><p class="quote-inline">RE: <a href="https://remote.example.com/1">link</a></p>')
      quote(post, create(:activity_pub_object, :remote, actor: author))

      expect(helper.content_without_quote_fallback(post)).to eq('<p>本文</p>')
    end

    it 'leaves posts that do not quote anything as they are' do
      post = create(:activity_pub_object, :remote, actor: author, content: '<p class="quote-inline">RE: x</p>')

      expect(helper.content_without_quote_fallback(post)).to eq('<p class="quote-inline">RE: x</p>')
    end
  end
end
