# frozen_string_literal: true

module ActivityBuilders
  class TagBuilder
    def initialize(object)
      @object = object
    end

    def build
      hashtag_tags + mention_tags + emoji_tags
    end

    private

    def hashtag_tags
      @object.tags.map do |tag|
        {
          'type' => 'Hashtag',
          'href' => "#{Rails.application.config.activitypub.base_url}/tags/#{tag.name}",
          'name' => "##{tag.name}"
        }
      end
    end

    def mention_tags
      @object.mentions.includes(:actor).map do |mention|
        mention_name = if mention.actor.local?
                         "@#{mention.actor.username}"
                       else
                         "@#{mention.actor.username}@#{mention.actor.domain}"
                       end

        {
          'type' => 'Mention',
          'href' => mention.actor.ap_id,
          'name' => mention_name
        }
      end
    end

    def emoji_tags
      return [] if @object.content.blank?

      emojis = EmojiPresenter.extract_emojis_from(@object.content)
      emojis.map do |emoji|
        {
          'type' => 'Emoji',
          'id' => "#{Rails.application.config.activitypub.base_url}/emojis/#{emoji.shortcode}",
          'name' => ":#{emoji.shortcode}:",
          'icon' => {
            'type' => 'Image',
            'mediaType' => 'image/png',
            'url' => emoji.image_url
          }
        }
      end
    end
  end
end
