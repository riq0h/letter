# frozen_string_literal: true

class TagUsageHistory < ApplicationRecord
  belongs_to :tag

  validates :date, presence: true, uniqueness: { scope: :tag_id }

  def self.record_usage(tag, _actor_id = nil)
    history = find_or_create_by(tag: tag, date: Date.current)
    history.increment!(:uses)
    # ユニークアカウント数を更新（同日の同タグ使用アカウントを集計）
    unique_accounts = ObjectTag.where(tag: tag)
                               .joins(:object)
                               .where(objects: { published_at: Date.current.beginning_of_day.. })
                               .joins('INNER JOIN actors ON actors.id = objects.actor_id')
                               .distinct
                               .count('actors.id')
    history.update_column(:accounts, unique_accounts)
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end
