# frozen_string_literal: true

class AccountStatusesQuery
  def initialize(account, current_user = nil, relation = nil)
    @account = account
    @current_user = current_user
    @relation = relation || default_relation
  end

  def call
    @relation
  end

  def pinned_only
    pinned_relation = @account.pinned_statuses
                              .includes(object: %i[actor media_attachments mentions tags poll])
                              .joins(:object)

    # 可視性フィルタリングを適用
    pinned_relation = apply_visibility_filters_to_pinned(pinned_relation)
    pinned_relation.ordered
  end

  def exclude_replies
    @relation = @relation.where(in_reply_to_ap_id: nil)
    self
  end

  def only_media
    @relation = @relation.joins(:media_attachments).distinct
    self
  end

  def paginate(max_id: nil, since_id: nil, min_id: nil)
    @relation = @relation.where(objects: { id: ...(max_id) }) if max_id.present?
    @relation = @relation.where('objects.id > ?', since_id) if since_id.present?
    @relation = @relation.where('objects.id > ?', min_id) if min_id.present?
    self
  end

  def exclude_pinned(pinned_ids)
    return self if pinned_ids.empty?

    @relation = @relation.where.not(id: pinned_ids)
    self
  end

  def with_includes
    @relation = @relation.includes(:poll, :actor, :media_attachments, :mentions, :tags)
    self
  end

  def ordered
    @relation = @relation.order(published_at: :desc)
    self
  end

  def limit(count)
    @relation = @relation.limit(count)
    self
  end

  private

  attr_reader :account, :current_user

  def default_relation
    relation = @account.objects.where(object_type: %w[Note Question])
                       .where(local: [true, false])

    apply_visibility_filters(relation)
  end

  def apply_visibility_filters(relation)
    # 常にダイレクトメッセージを除外
    relation = relation.where.not(visibility: 'direct')

    relation.where(visibility: allowed_visibility_levels)
  end

  def apply_visibility_filters_to_pinned(pinned_relation)
    # 常にダイレクトメッセージを除外
    pinned_relation = pinned_relation.where.not(objects: { visibility: 'direct' })

    pinned_relation.where(objects: { visibility: allowed_visibility_levels })
  end

  def allowed_visibility_levels
    if current_user
      if current_user == account || Follow.exists?(actor: current_user, target_actor: account, accepted: true)
        # 自分のアカウント or フォロー中の場合：public, unlisted, private を表示
        %w[public unlisted private]
      else
        # フォローしていない場合：public, unlisted のみ表示
        %w[public unlisted]
      end
    else
      # 未認証ユーザ：public のみ表示
      %w[public]
    end
  end
end
