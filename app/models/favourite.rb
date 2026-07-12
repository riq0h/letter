# frozen_string_literal: true

class Favourite < ApplicationRecord
  include ApIdGeneration
  include NotificationCreation
  include ObjectCounterManagement

  # 旧Misskey(v10系)の名前付きリアクション → Unicode絵文字の対応表(Misskey本家準拠)。
  # 現行Misskeyも後方互換でこの名前(例: star)をLikeのcontentに載せて送ってくることがある
  LEGACY_MISSKEY_REACTIONS = {
    'like' => '👍', 'love' => '❤', 'laugh' => '😆', 'hmm' => '🤔',
    'surprise' => '😮', 'congrats' => '🎉', 'angry' => '💢',
    'confused' => '😥', 'rip' => '😇', 'pudding' => '🍮', 'star' => '⭐'
  }.freeze

  belongs_to :actor, class_name: 'Actor'
  belongs_to :object, class_name: 'ActivityPubObject'

  validates :actor_id, uniqueness: { scope: :object_id }

  scope :recent, -> { order(created_at: :desc) }

  tracks_object_counter :favourites_count
  after_create :create_notification_for_favourite
end
