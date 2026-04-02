# frozen_string_literal: true

require_relative '../controllers/concerns/activity_pub_visibility_helper'

class RelayAnnounceProcessorJob < ApplicationJob
  include ActivityPubHelper
  include ActivityPubMediaHandler
  include ActivityPubVisibilityHelper
  include ActivityPubUtilityHelpers

  queue_as :default

  def perform(announce_activity, relay_id)
    @relay = Relay.find_by(id: relay_id)
    return unless @relay&.accepted?

    @announce_activity = announce_activity
    @object_id = announce_activity['object']

    # 元のオブジェクトを取得
    object_data = fetch_activitypub_object(@object_id)
    return unless object_data

    # 既存チェック
    return if ActivityPubObject.exists?(ap_id: @object_id)

    # オブジェクトの種類によって処理を分岐
    case object_data['type']
    when 'Note', 'Article'
      process_note_object(object_data)
    when 'Create'
      process_create_activity(object_data)
    else
      Rails.logger.warn "Unsupported object type from relay: #{object_data['type']}"
    end
  rescue StandardError => e
    Rails.logger.error "Relay announce processing error: #{e.message}"
  end

  private

  def process_note_object(note_data)
    # 投稿者のアクター情報を取得
    actor_id = note_data['attributedTo'] || note_data['actor']
    return unless actor_id

    actor_data = fetch_activitypub_object(actor_id)
    return unless actor_data

    # アクターを作成または取得
    actor = find_or_create_actor(actor_data)
    return unless actor

    # 投稿オブジェクトを作成
    create_activity_pub_object(note_data, actor)
  end

  def process_create_activity(create_data)
    # Createアクティビティの場合
    actor_id = create_data['actor']
    object_data = create_data['object']

    return unless actor_id && object_data

    actor_data = fetch_activitypub_object(actor_id)
    return unless actor_data

    actor = find_or_create_actor(actor_data)
    return unless actor

    # objectがStringの場合は取得
    if object_data.is_a?(String)
      object_data = fetch_activitypub_object(object_data)
      return unless object_data
    end

    create_activity_pub_object(object_data, actor)
  end

  def find_or_create_actor(actor_data)
    actor_id = actor_data['id']
    existing_actor = Actor.find_by(ap_id: actor_id)
    return existing_actor if existing_actor

    # 新しいアクターを作成
    actor_fetcher = ActorFetcher.new
    actor_fetcher.create_actor_from_data(actor_id, actor_data)
  rescue StandardError => e
    Rails.logger.error "Failed to create actor from relay: #{e.message}"
    nil
  end

  def create_activity_pub_object(object_data, actor)
    # 投稿の可視性を判断
    visibility = determine_visibility(object_data)

    # ローカルタイムラインに表示しない（リレー投稿はpublic扱い）
    visibility = 'public' if visibility == 'unlisted'

    object = ActivityPubObject.create!(
      ap_id: object_data['id'],
      object_type: 'Note',
      actor: actor,
      content: object_data['content'] || '',
      published_at: parse_published_date(object_data['published']),
      visibility: visibility,
      raw_data: object_data.to_json,
      local: false,
      # リレー経由であることを明示
      relay_id: @relay.id
    )

    handle_media_attachments(object, object_data)
    # HomeFeedへの追加はActivityPubObjectのafter_commitで実行される
    object
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create ActivityPub object from relay: #{e.message}"
  end
end
