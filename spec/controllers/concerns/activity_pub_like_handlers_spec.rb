# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPubLikeHandlers, type: :controller do
  controller(ApplicationController) do
    include ActivityPubUtilityHelpers
    include ActivityPubLikeHandlers # rubocop:disable RSpec/DescribedClass -- 匿名コントローラ内はincludeに定数が必要

    skip_before_action :verify_authenticity_token

    def test_like_action
      # 実運用ではJSON.parse由来の素のHashが入るため、Parametersから復元する
      @activity = params[:activity].to_unsafe_h
      @sender = Actor.find(params[:sender_id])
      handle_like_activity
    end
  end

  let(:local_actor) { create(:actor, local: true) }
  let(:remote_actor) { create(:actor, :remote, domain: 'misskey.example.com') }
  let(:status) { create(:activity_pub_object, actor: local_actor) }

  before do
    routes.draw { post 'test_like_action' => 'anonymous#test_like_action' }
  end

  def like_activity(overrides = {})
    {
      '@context' => 'https://www.w3.org/ns/activitystreams',
      'id' => "https://misskey.example.com/likes/#{SecureRandom.hex(8)}",
      'type' => 'Like',
      'actor' => remote_actor.ap_id,
      'object' => status.ap_id
    }.merge(overrides)
  end

  def perform(activity)
    post :test_like_action, params: { activity: activity, sender_id: remote_actor.id }
  end

  describe 'reaction extraction' do
    it 'stores a plain like with reaction nil (Mastodon-style)' do
      expect { perform(like_activity) }.to change(Favourite, :count).by(1)
      expect(Favourite.last.reaction).to be_nil
    end

    it 'stores a unicode emoji reaction from content' do
      perform(like_activity('content' => '👍'))
      expect(Favourite.last.reaction).to eq('👍')
    end

    it 'normalizes a Misskey local custom emoji (:name@.:) to :name:' do
      perform(like_activity('content' => ':igyo@.:'))
      expect(Favourite.last.reaction).to eq(':igyo:')
    end

    it 'normalizes a remote custom emoji (:Name@domain:) to lowercase :name:' do
      perform(like_activity('content' => ':BlobCat_Nod@misskey.io:'))
      expect(Favourite.last.reaction).to eq(':blobcat_nod:')
    end

    it 'falls back to _misskey_reaction when content is absent' do
      perform(like_activity('_misskey_reaction' => '🙏'))
      expect(Favourite.last.reaction).to eq('🙏')
    end

    it 'maps a legacy Misskey named reaction (star) to its unicode emoji' do
      perform(like_activity('content' => 'star'))
      expect(Favourite.last.reaction).to eq('⭐')
    end

    it 'maps legacy names arriving via _misskey_reaction too' do
      perform(like_activity('_misskey_reaction' => 'pudding'))
      expect(Favourite.last.reaction).to eq('🍮')
    end

    it 'handles EmojiReact payloads the same way (activity saved as Like)' do
      perform(like_activity('type' => 'EmojiReact', 'content' => '🎉'))

      expect(Favourite.last.reaction).to eq('🎉')
      expect(Activity.find_by(ap_id: Favourite.last.ap_id).activity_type).to eq('Like')
    end
  end

  describe 'custom emoji tag capture' do
    it 'creates a CustomEmoji from the reaction tag (keyed by sender domain)' do
      activity = like_activity(
        'content' => ':igyo@.:',
        'tag' => [{ 'type' => 'Emoji', 'name' => ':igyo:', 'icon' => { 'url' => 'https://misskey.example.com/e/igyo.png' } }]
      )

      expect { perform(activity) }.to change(CustomEmoji, :count).by(1)
      emoji = CustomEmoji.last
      expect(emoji.shortcode).to eq('igyo')
      expect(emoji.domain).to eq('misskey.example.com')
    end
  end

  describe 'reaction backfill on existing favourite' do
    it 'fills reaction when a reaction arrives for an existing plain favourite' do
      create(:favourite, actor: remote_actor, object: status)

      expect { perform(like_activity('content' => '👍')) }.not_to change(Favourite, :count)
      expect(Favourite.last.reaction).to eq('👍')
    end

    it 'does not overwrite an existing reaction' do
      create(:favourite, actor: remote_actor, object: status, reaction: '🙏')

      perform(like_activity('content' => '👍'))
      expect(Favourite.last.reaction).to eq('🙏')
    end
  end
end
