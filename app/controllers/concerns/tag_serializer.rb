# frozen_string_literal: true

module TagSerializer
  extend ActiveSupport::Concern

  private

  def serialized_tag(tag, include_history: true)
    result = {
      name: tag.name,
      url: "#{request.base_url}/tags/#{tag.name}"
    }

    result[:history] = if include_history
                         [
                           {
                             day: Time.current.to_date.to_s,
                             uses: tag.usage_count.to_s,
                             accounts: calculate_tag_accounts_count(tag).to_s
                           }
                         ]
                       else
                         []
                       end

    result
  end

  def calculate_tag_accounts_count(tag)
    # 今日タグを使用したユニークなアカウント数を計算
    # パフォーマンスを考慮して、キャッシュを使用することを推奨
    tag.object_tags
       .joins(object: :actor)
       .where(objects: { published_at: Time.current.beginning_of_day.. })
       .distinct
       .count('actors.id')
  rescue StandardError => e
    Rails.logger.error "Failed to calculate tag accounts count: #{e.message}"
    1 # エラー時はフォールバック値を返す
  end
end
