# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPubObjectSerializer do
  let(:me) { create(:actor) }
  let(:author) { create(:actor, :remote) }
  let(:quoted) { create(:activity_pub_object, :remote, actor: author, url: 'https://remote.example.com/@kana/1') }

  def quote!(post)
    QuotePost.create!(actor: me, object: post, quoted_object: quoted, ap_id: "#{post.ap_id}#quote")
  end

  describe 'the RE: line for servers that do not understand quotes' do
    it 'is put before the text when the text does not link the quoted post' do
      post = create(:activity_pub_object, actor: me, content: '<p>なるほど</p>')
      quote!(post)

      content = described_class.new(post).to_activitypub['content']

      expect(content).to start_with(%(<p class="quote-inline">RE: <a href="#{quoted.public_url}">))
      expect(content).to end_with('<p>なるほど</p>')
    end

    it 'is not added when the text already links the quoted post' do
      post = create(:activity_pub_object, actor: me, content: "<p>なるほど #{quoted.public_url}</p>")
      quote!(post)

      expect(described_class.new(post).to_activitypub['content']).not_to include('quote-inline')
    end

    it 'is not stored in the post itself' do
      post = create(:activity_pub_object, actor: me, content: '<p>なるほど</p>')
      quote!(post)
      described_class.new(post).to_activitypub

      expect(post.reload.content).to eq('<p>なるほど</p>')
    end

    it 'is not added to posts that quote nothing' do
      post = create(:activity_pub_object, actor: me, content: '<p>ふつう</p>')

      expect(described_class.new(post).to_activitypub['content']).to eq('<p>ふつう</p>')
    end
  end

  it 'publishes the quote setting of the post' do
    post = create(:activity_pub_object, actor: me, quote_policy: 'followers')

    expect(described_class.new(post).to_activitypub['interactionPolicy'])
      .to eq('canQuote' => { 'automaticApproval' => [me.followers_url] })
  end
end
