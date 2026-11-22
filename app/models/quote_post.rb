# frozen_string_literal: true

class QuotePost < ApplicationRecord
  include RemoteLocalHelper
  include ActivityDeliveryHelper

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
  # 承認の証明を出せるのは、引用された投稿の作者のサーバだけ
  after_create :create_self_authorization!, if: -> { quoted_object.actor&.local? }
  after_create_commit :request_quote_approval, if: :needs_remote_approval?

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
    return unless has_attribute?(:interaction_policy)

    self.interaction_policy ||= {
      'canQuote' => {
        'automaticApproval' => ['https://www.w3.org/ns/activitystreams#Public']
      }
    }
  end

  # 承認を求めるQuoteRequestのid。作者のサーバの応答(Accept/Reject)はこのidを指して届く
  def quote_request_ap_id
    "#{actor.ap_id}#quote_requests/#{id}"
  end

  def self.from_quote_request_ap_id(uri)
    quote_post = find_by(id: uri.to_s[/#quote_requests\/(\d+)\z/, 1])
    quote_post if quote_post&.quote_request_ap_id == uri
  end

  # letterの投稿objectがquoted_objectを引用したことを記録する
  def self.record_local!(object, quoted_object)
    create!(
      actor: object.actor,
      object: object,
      quoted_object: quoted_object,
      shallow_quote: object.content.blank?,
      quote_text: object.content,
      visibility: object.visibility,
      ap_id: "#{object.ap_id}#quote"
    )
  end

  def approved?
    quote_authorization_url.present?
  end

  # 引用された投稿の作者(こちら)が引用を取り消す。承認の証明を削除したことを、引用した側と
  # こちらのフォロワーのサーバに伝え(Mastodon 4.5と同じ)、引用の記録と承認の証明を消す
  def revoke!
    authorization = quote_authorization
    quoting = object
    transaction do
      announce_revocation(authorization) if authorization
      destroy!
    end
    # こちらの投稿による引用なら、引用を外した投稿を配信し直す
    quoting.redistribute! if actor.local?
  end

  # 他サーバの投稿を引用して、作者のサーバの承認をまだ受けていないか。
  # 承認の仕組みを持つサーバ(投稿に引用の許可設定がある)のときだけ。持たないサーバ
  # (Misskeyなど)は返事をしないので、承認待ちとは扱わない
  def awaiting_approval?
    needs_remote_approval? && !approved? && QuotePolicy.new(quoted_object).declared?
  end

  # 自己完結型引用承認を作成。interactingObjectは引用した投稿そのもの(FEP-044f。
  # Mastodonは承認を受け取ると、これが引用した投稿のURIと一致するかを確かめる)
  def create_self_authorization!
    return if quote_authorization.present?

    auth_id = "#{Rails.application.config.activitypub.base_url}/quote_auth/#{SecureRandom.hex(16)}"

    self.quote_authorization = QuoteAuthorization.create!(
      ap_id: auth_id,
      actor: quoted_object.actor,
      quote_post: self,
      interacting_object_id: object.ap_id,
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
    return {} unless quoted_object

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

  # 他サーバの投稿を引用したときは、作者のサーバに承認を求める(FEP-044f。Mastodon 4.5以降)
  def needs_remote_approval?
    actor&.local? && quoted_object.actor.present? && !quoted_object.actor.local?
  end

  def request_quote_approval
    SendQuoteRequestJob.perform_later(id)
  end

  def announce_revocation(authorization)
    owner = quoted_object.actor
    activity = Activity.create!(
      ap_id: "#{authorization.ap_id}#delete",
      activity_type: 'Delete',
      actor: owner,
      target_ap_id: authorization.ap_id,
      published_at: Time.current,
      local: true
    )
    inboxes = Actor.delivery_inboxes(owner.followers)
    inboxes.unshift(actor.preferred_inbox) unless actor.local?
    enqueue_send_activity(activity, inboxes.compact.uniq)
  end

  def notify_quoted_status_author
    # 受信者がリモートユーザの通知は作成しない（読まれることがない）
    return unless quoted_object.actor&.local?
    # 自分自身の投稿を引用した場合は通知しない
    return if quoted_object.actor == actor

    # 引用された投稿の作者に通知を送信
    Notification.create_quote_notification(self, quoted_object)
  rescue StandardError => e
    Rails.logger.error "Failed to create quote notification: #{e.message}"
  end
end
