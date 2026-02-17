# frozen_string_literal: true

class Reblog < ApplicationRecord
  include ApIdGeneration
  include NotificationCreation
  include ObjectCounterManagement

  belongs_to :actor, class_name: 'Actor'
  belongs_to :object, class_name: 'ActivityPubObject'

  validates :actor_id, uniqueness: { scope: :object_id }

  tracks_object_counter :reblogs_count
  after_create :create_notification_for_reblog

  # created_atとidからSnowflake互換IDを導出する
  # タイムスタンプ部分はcreated_at、シーケンス部分はid % 65536
  def timeline_id
    timestamp_ms = Letter::Snowflake.timestamp_to_ms(created_at)
    sequence = id % (1 << Letter::Snowflake::SEQUENCE_BITS)
    ((timestamp_ms << Letter::Snowflake::SEQUENCE_BITS) | sequence).to_s
  end
end
