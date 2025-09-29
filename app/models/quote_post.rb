# frozen_string_literal: true

class QuotePost < ApplicationRecord
  include RemoteLocalHelper

  belongs_to :actor
  belongs_to :object, class_name: 'ActivityPubObject', primary_key: :id
  belongs_to :quoted_object, class_name: 'ActivityPubObject', primary_key: :id
  has_one :quote_authorization, dependent: :destroy

  validates :object_id, uniqueness: { scope: :quoted_object_id }
  validates :visibility, inclusion: { in: ActivityPubObject::VISIBILITY_LEVELS }
  validates :ap_id, presence: true, uniqueness: true

  # コールバック
  before_save :set_default_interaction_policy
  after_create :notify_quoted_status_author
  after_create :create_self_authorization!

  scope :recent, -> { order(created_at: :desc) }
  scope :shallow, -> { where(shallow_quote: true) }
  scope :deep, -> { where(shallow_quote: false) }
  scope :public_quotes, -> { where(visibility: 'public') }

  # Shallow Quote: 引用元のポストを単純に再共有（追加テキストなし）
  def shallow_quote?
    shallow_quote
  end

  # Deep Quote: 引用元のポストに追加のコメント/テキストを付けて共有
  def deep_quote?
    !shallow_quote
  end

  delegate :local?, to: :actor

  # 引用許可ポリシーを設定（デフォルトは全員許可）
  def set_default_interaction_policy
    self.interaction_policy ||= {
      'canQuote' => {
        'automaticApproval' => ['https://www.w3.org/ns/activitystreams#Public']
      }
    }
  end

  # 自己完結型引用承認を作成
  def create_self_authorization!
    return if quote_authorization.present?

    auth_id = "#{Rails.application.config.activitypub.base_url}/quote_auth/#{SecureRandom.hex(16)}"

    self.quote_authorization = QuoteAuthorization.create!(
      ap_id: auth_id,
      actor: quoted_object.actor,
      quote_post: self,
      interacting_object_id: ap_id,
      interaction_target_id: quoted_object.ap_id
    )

    self.quote_authorization_url = auth_id
    save!
  end

  # ActivityPub JSON-LD representation
  def to_activitypub
    base_data.merge(quote_properties).tap do |json|
      json['content'] = quote_text if deep_quote? && quote_text.present?
      json['quoteAuthorization'] = quote_authorization_url if quote_authorization_url.present?
      json['interactionPolicy'] = interaction_policy if interaction_policy.present?
    end.compact
  end

  private

  def base_data
    {
      '@context' => fep044f_context,
      'id' => ap_id,
      'type' => 'Note',
      'actor' => actor.ap_id,
      'published' => created_at.iso8601,
      'to' => build_audience_list(:to),
      'cc' => build_audience_list(:cc)
    }
  end

  def quote_properties
    {
      'quote' => quoted_object.ap_id,
      'quoteUrl' => quoted_object.ap_id,
      'quoteUri' => quoted_object.ap_id,
      '_misskey_quote' => quoted_object.ap_id
    }
  end

  def fep044f_context
    [
      'https://www.w3.org/ns/activitystreams',
      {
        'quote' => {
          '@id' => 'https://w3id.org/fep/044f#quote',
          '@type' => '@id'
        },
        'quoteAuthorization' => {
          '@id' => 'https://w3id.org/fep/044f#quoteAuthorization',
          '@type' => '@id'
        },
        'gts' => 'https://gotosocial.org/ns#',
        'interactionPolicy' => {
          '@id' => 'gts:interactionPolicy',
          '@type' => '@id'
        },
        'canQuote' => {
          '@id' => 'gts:canQuote',
          '@type' => '@id'
        },
        'automaticApproval' => {
          '@id' => 'gts:automaticApproval',
          '@type' => '@id'
        }
      }
    ]
  end

  def build_audience_list(type)
    ActivityBuilders::AudienceBuilder.new(self).build(type)
  end

  def notify_quoted_status_author
    # 自分自身の投稿を引用した場合は通知しない
    return if quoted_object.actor == actor

    # 引用された投稿の作者に通知を送信
    Notification.create_quote_notification(self, quoted_object)
  rescue StandardError => e
    Rails.logger.error "Failed to create quote notification: #{e.message}"
  end
end
