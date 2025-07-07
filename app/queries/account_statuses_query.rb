# frozen_string_literal: true

class AccountStatusesQuery
  def initialize(account, relation = nil)
    @account = account
    @relation = relation || default_relation
  end

  def call
    @relation
  end

  def pinned_only
    @account.pinned_statuses
            .includes(object: %i[actor media_attachments mentions tags poll])
            .ordered
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

  attr_reader :account

  def default_relation
    @account.objects.where(object_type: %w[Note Question])
            .where(local: [true, false])
  end
end
