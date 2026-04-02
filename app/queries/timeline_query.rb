# frozen_string_literal: true

class TimelineQuery
  def initialize(user, params = {})
    @user = user
    @params = params
  end

  def build_home_timeline
    if HomeFeedManager.populated?
      build_home_timeline_from_feed
    else
      build_home_timeline_legacy
    end
  end

  def build_home_timeline_legacy
    followed_ids = user.followed_actors.pluck(:id) + [user.id]

    statuses = base_timeline_query.where(actor_id: followed_ids)

    # フォロー中タグの投稿を追加
    followed_tag_ids = user.followed_tags.pluck(:tag_id)
    if followed_tag_ids.any?
      tag_object_ids = ObjectTag.where(tag_id: followed_tag_ids)
                                .joins(object: :actor)
                                .where(objects: { visibility: 'public', object_type: %w[Note Question] })
                                .pluck(:object_id)
      statuses = statuses.or(base_timeline_query.where(objects: { id: tag_object_ids })) if tag_object_ids.any?
    end

    statuses = apply_pagination_filters(statuses).limit(limit * 2)

    reblogs = fetch_reblogs(followed_ids)

    MergedTimeline.merge(statuses, reblogs, limit).to_a
  end

  def build_home_timeline_from_feed
    # フィードテーブルからエントリ取得（キャッシュDB — プライマリDBとロック競合なし）
    entries = HomeFeedEntry.order(Arel.sql('sort_id DESC'))
    entries = entries.where(sort_id: ...(params[:max_id])) if params[:max_id].present?
    entries = entries.where('sort_id > ?', params[:since_id]) if params[:since_id].present? && params[:min_id].blank?
    entries = entries.where('sort_id > ?', params[:min_id]) if params[:min_id].present?

    # ブロック・ミュートフィルタ（actor_idベース）
    blocked_ids = user.blocked_actors.pluck(:id)
    muted_ids = user.muted_actors.pluck(:id)
    entries = entries.where.not(actor_id: blocked_ids) if blocked_ids.any?
    entries = entries.where.not(actor_id: muted_ids) if muted_ids.any?

    # ドメインブロック（プライマリDBからactor_idに変換）
    blocked_domains = user.domain_blocks.pluck(:domain)
    if blocked_domains.any?
      domain_blocked_actor_ids = Actor.where(domain: blocked_domains).pluck(:id)
      entries = entries.where.not(actor_id: domain_blocked_actor_ids) if domain_blocked_actor_ids.any?
    end

    entries = entries.limit(limit * 2).to_a

    # フィードが空ならlegacyにフォールバック
    return build_home_timeline_legacy if entries.empty? && params[:max_id].blank? && params[:since_id].blank?

    # エントリをステータスとリブログに分離
    status_entries = entries.select { |e| e.reblog_id.nil? }
    reblog_entries = entries.reject { |e| e.reblog_id.nil? }

    # プライマリDBからオブジェクトとリブログを一括取得
    statuses = load_statuses_from_entries(status_entries)
    reblogs = load_reblogs_from_entries(reblog_entries)

    # DMフィルタとリプライフィルタをRuby側で適用
    statuses = apply_ruby_filters(statuses, user)

    # sort_id順に再構成
    sort_order = entries.map(&:sort_id)
    build_sorted_timeline(statuses, reblogs, sort_order, limit)
  end

  def build_public_timeline
    statuses = base_timeline_query.where(visibility: 'public')
    statuses = statuses.where(actors: { local: true }) if local_only?
    apply_pagination_filters(statuses).limit(limit)
  end

  def build_hashtag_timeline(hashtag_name)
    normalized_name = hashtag_name.unicode_normalize(:nfkc).strip.downcase
    tag = Tag.find_by(name: normalized_name)
    return ActivityPubObject.none unless tag

    statuses = base_timeline_query
               .joins(:tags)
               .where(tags: { id: tag.id })
    statuses = apply_hashtag_visibility_filter(statuses)
    apply_pagination_filters(statuses).limit(limit)
  end

  def build_list_timeline(list)
    member_ids = list.list_memberships.pluck(:actor_id)
    return ActivityPubObject.none if member_ids.empty?

    statuses = base_timeline_query.where(actor_id: member_ids)
    apply_pagination_filters(statuses).limit(limit)
  end

  private

  attr_reader :user, :params

  def limit
    params[:limit] || 20
  end

  def local_only?
    params[:local].present? && params[:local] != 'false'
  end

  # 認証済みユーザの場合、フォロー中アクターの非公開投稿もタグタイムラインに含める
  def apply_hashtag_visibility_filter(statuses)
    if user
      followed_ids = user.followed_actors.pluck(:id) + [user.id]
      statuses.where(visibility: 'public')
              .or(statuses.where(visibility: 'private', actor_id: followed_ids))
    else
      statuses.where(visibility: 'public')
    end
  end

  def base_timeline_query
    query = ActivityPubObject.joins(:actor)
                             .includes(actor: { avatar_attachment: :blob, header_attachment: :blob },
                                       media_attachments: { file_attachment: :blob, thumbnail_attachment: :blob },
                                       poll: [], tags: [],
                                       mentions: { actor: { avatar_attachment: :blob, header_attachment: :blob } })
                             .where(object_type: %w[Note Question])
                             .where(is_pinned_only: false)
                             .order('objects.id DESC')

    query = UserTimelineQuery.new(user).apply(query) if user
    query
  end

  def fetch_reblogs(followed_ids)
    reblogs = Reblog.joins(:actor, :object)
                    .where(actor_id: followed_ids)
                    .where(objects: { visibility: %w[public unlisted] })
                    .includes(object: [{ actor: { avatar_attachment: :blob, header_attachment: :blob } },
                                       { media_attachments: { file_attachment: :blob, thumbnail_attachment: :blob } },
                                       :poll, :tags,
                                       { mentions: { actor: { avatar_attachment: :blob, header_attachment: :blob } } }],
                              actor: { avatar_attachment: :blob, header_attachment: :blob })
                    .order('reblogs.created_at DESC')
    apply_reblog_pagination_filters(reblogs).limit(limit * 2)
  end

  def apply_pagination_filters(query)
    query = query.where(objects: { id: ...(params[:max_id]) }) if params[:max_id].present?
    query = query.where('objects.id > ?', params[:since_id]) if params[:since_id].present? && params[:min_id].blank?
    query = query.where('objects.id > ?', params[:min_id]) if params[:min_id].present?
    query
  end

  def apply_reblog_pagination_filters(query)
    if params[:max_id].present?
      max_time = snowflake_to_time(params[:max_id])
      query = query.where(reblogs: { created_at: ...max_time }) if max_time
    end
    if params[:since_id].present? && params[:min_id].blank?
      since_time = snowflake_to_time(params[:since_id])
      query = query.where('reblogs.created_at > ?', since_time) if since_time
    end
    if params[:min_id].present?
      min_time = snowflake_to_time(params[:min_id])
      query = query.where('reblogs.created_at > ?', min_time) if min_time
    end
    query
  end

  def snowflake_to_time(id)
    return nil if id.blank?

    Letter::Snowflake.extract_timestamp(id)
  rescue ArgumentError, RangeError
    nil
  end

  # フィードベースのタイムライン構築用ヘルパー

  def load_statuses_from_entries(entries)
    return [] if entries.empty?

    object_ids = entries.map(&:object_id)
    ActivityPubObject.joins(:actor)
                     .includes(actor: { avatar_attachment: :blob, header_attachment: :blob },
                               media_attachments: { file_attachment: :blob, thumbnail_attachment: :blob },
                               poll: [], tags: [],
                               mentions: { actor: { avatar_attachment: :blob, header_attachment: :blob } })
                     .where(id: object_ids)
                     .to_a
  end

  def load_reblogs_from_entries(entries)
    return [] if entries.empty?

    reblog_ids = entries.map(&:reblog_id)
    Reblog.joins(:actor, :object)
          .includes(object: [{ actor: { avatar_attachment: :blob, header_attachment: :blob } },
                             { media_attachments: { file_attachment: :blob, thumbnail_attachment: :blob } },
                             :poll, :tags,
                             { mentions: { actor: { avatar_attachment: :blob, header_attachment: :blob } } }],
                    actor: { avatar_attachment: :blob, header_attachment: :blob })
          .where(id: reblog_ids)
          .to_a
  end

  def apply_ruby_filters(statuses, user)
    followed_ids = user.followed_actors.pluck(:id) + [user.id]

    statuses.reject do |s|
      # DMフィルタ
      s.visibility == 'direct' ||
        # リプライフィルタ: リプライで、自分宛メンションでもフォロー先への返信でもない場合は除外
        (s.in_reply_to_ap_id.present? &&
         s.mentions.none? { |m| m.actor_id == user.id } &&
         !reply_to_followed?(s, followed_ids))
    end
  end

  def reply_to_followed?(status, followed_ids)
    reply_object = ActivityPubObject.find_by(ap_id: status.in_reply_to_ap_id)
    reply_object && followed_ids.include?(reply_object.actor_id)
  end

  def build_sorted_timeline(statuses, reblogs, sort_order, limit)
    # sort_idからオブジェクトへのマップを構築
    items_by_sort_id = {}

    statuses.each { |s| items_by_sort_id[s.id.to_s] = s }
    reblogs.each { |r| items_by_sort_id[r.timeline_id] = r }

    # sort_order順に並べて返却
    result = sort_order.filter_map { |sort_id| items_by_sort_id[sort_id] }
    result.first(limit)
  end
end
