# frozen_string_literal: true

require 'rails_helper'

# Update(Person)受信時にプロフィールのカスタム絵文字(tag)を取り込む
RSpec.describe ActivityPubObjectHandlers do
  let(:harness_class) do
    Class.new do
      include ActivityPubObjectHandlers

      def initialize(sender)
        @sender = sender
      end

      def run(object_data)
        update_actor_profile(object_data)
      end
    end
  end

  let(:sender) { create(:actor, :remote, domain: 'mastodon.likids.info', display_name: 'naru :mastodon:') }
  let(:new_url) { 'https://mastodon.likids.info/system/custom_emojis/images/000/155/469/original/new.png' }
  let(:object_data) do
    {
      'id' => sender.ap_id,
      'type' => 'Person',
      'name' => 'naru :mastodon:',
      'tag' => [{ 'type' => 'Emoji', 'name' => ':mastodon:', 'icon' => { 'type' => 'Image', 'url' => new_url } }]
    }
  end

  before do
    creation = instance_double(ActorCreationService)
    allow(ActorCreationService).to receive(:new).and_return(creation)
    allow(creation).to receive(:send).with(:attach_remote_images, anything, anything)
  end

  it 'updates the stale image URL of a profile emoji' do
    emoji = create(:custom_emoji, :remote, shortcode: 'mastodon', domain: 'mastodon.likids.info',
                                           image_url: 'https://mastodon.likids.info/old.png')

    harness_class.new(sender).run(object_data)

    expect(emoji.reload.image_url).to eq(new_url)
  end

  it 'creates a profile emoji that was unknown' do
    harness_class.new(sender).run(object_data)

    expect(CustomEmoji.find_by(shortcode: 'mastodon', domain: 'mastodon.likids.info')&.image_url).to eq(new_url)
  end
end
