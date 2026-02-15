# frozen_string_literal: true

module EmojiFiltering
  extend ActiveSupport::Concern

  private

  def base_emoji_scope_for_tab(tab)
    scope = CustomEmoji.includes(:image_attachment)

    scope = case tab
            when 'remote'
              scope.remote
            else
              scope.local # デフォルトはローカル（'local'タブまたは他の値）
            end

    scope.order(created_at: :desc)
  end

  def apply_emoji_filters(scope)
    scope = filter_by_category(scope)
    scope = filter_by_search(scope)
    scope = filter_by_domain(scope)
    paginate_emojis(scope)
  end

  def filter_by_category(scope)
    return scope if params[:category].blank?

    scope.where(category_id: params[:category])
  end

  def filter_by_search(scope)
    return scope if params[:q].blank?

    sanitized_q = ActiveRecord::Base.sanitize_sql_like(params[:q])
    search_term = "%#{sanitized_q}%"
    scope.where('shortcode LIKE ? OR category_id LIKE ?', search_term, search_term)
  end

  def filter_by_domain(scope)
    return scope if params[:domain].blank?

    scope.where(domain: params[:domain])
  end

  def paginate_emojis(scope)
    scope.page(params[:page]).per(50)
  end
end
