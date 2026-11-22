# frozen_string_literal: true

class TagUsageHistory < ApplicationRecord
  belongs_to :tag

  validates :date, presence: true, uniqueness: { scope: :tag_id }

  def self.record_usage(tag, _actor_id = nil)
    history = find_or_create_by(tag: tag, date: Date.current)
    history.increment!(:uses)
    # 今日このタグを使ったアカウント数。今日付いたタグだけから数える(タグの全使用分を投稿と
    # 突き合わせると、よく使われるタグで1回1秒を超え、受信処理が遅くなる)
    unique_accounts = ObjectTag.where(tag: tag, created_at: Date.current.beginning_of_day..)
                               .joins(:object)
                               .distinct
                               .count('objects.actor_id')
    history.update_column(:accounts, unique_accounts)
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end
