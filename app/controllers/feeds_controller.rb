# frozen_string_literal: true

class FeedsController < ApplicationController
  before_action :set_cache_headers

  # ユーザ個別のRSSフィード
  def user
    @actor = Actor.local.find_by!(username: params[:username])
    # 公開・未収載のみ(フォロワー限定・DMを公開フィードに載せない)
    @posts = @actor.objects
                   .where(object_type: 'Note', visibility: %w[public unlisted])
                   .where.not(published_at: nil)
                   .includes(:actor, :media_attachments)
                   .order(published_at: :desc)
                   .limit(20)

    respond_to do |format|
      format.rss { render layout: false }
    end
  end

  # ローカルタイムラインのAtomフィード(公開タイムラインと同じく公開投稿のみ)
  def local
    @posts = ActivityPubObject.joins(:actor)
                              .where(actors: { domain: nil })
                              .where(object_type: 'Note', visibility: 'public')
                              .where.not(published_at: nil)
                              .includes(:actor, :media_attachments)
                              .order(published_at: :desc)
                              .limit(50)

    respond_to do |format|
      format.atom { render layout: false }
    end
  end

  private

  def set_cache_headers
    response.headers['Cache-Control'] = 'public, max-age=300'
  end
end
