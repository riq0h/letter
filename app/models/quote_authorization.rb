# frozen_string_literal: true

class QuoteAuthorization < ApplicationRecord
  belongs_to :actor
  belongs_to :quote_post

  validates :ap_id, presence: true, uniqueness: true
  validates :interacting_object_id, presence: true
  validates :interaction_target_id, presence: true

  # ActivityPub JSON-LD representation
  def to_activitypub
    {
      '@context' => [
        'https://www.w3.org/ns/activitystreams',
        {
          'QuoteAuthorization' => 'https://w3id.org/fep/044f#QuoteAuthorization',
          'gts' => 'https://gotosocial.org/ns#',
          'interactingObject' => {
            '@id' => 'gts:interactingObject',
            '@type' => '@id'
          },
          'interactionTarget' => {
            '@id' => 'gts:interactionTarget',
            '@type' => '@id'
          }
        }
      ],
      'type' => 'QuoteAuthorization',
      'id' => ap_id,
      'attributedTo' => actor.ap_id,
      'interactingObject' => interacting_object_id,
      'interactionTarget' => interaction_target_id
    }
  end

  # 引用の妥当性を検証
  def self.validate_quote(quote_post_ap_id, quoted_object_ap_id, quote_authorization_url)
    return false if quote_authorization_url.blank?

    begin
      # QuoteAuthorizationを取得
      auth = find_by(ap_id: quote_authorization_url)
      return false unless auth

      # 4つの要素を検証
      auth.ap_id == quote_authorization_url &&
        auth.interacting_object_id == quote_post_ap_id &&
        auth.interaction_target_id == quoted_object_ap_id &&
        auth.actor == ActivityPubObject.find_by(ap_id: quoted_object_ap_id)&.actor
    rescue StandardError => e
      Rails.logger.error "Quote validation failed: #{e.message}"
      false
    end
  end
end
