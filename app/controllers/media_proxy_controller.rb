# frozen_string_literal: true

class MediaProxyController < ApplicationController
  # GET /media_proxy/:id
  def show
    media = MediaAttachment.find_by(id: params[:id])
    return head :not_found unless media

    if media.file.attached?
      redirect_to media.url, allow_other_host: true
    elsif media.remote_url.present?
      RemoteMediaDownloadJob.perform_later(media.id)
      redirect_to media.remote_url, allow_other_host: true
    else
      head :not_found
    end
  end

  # GET /media_proxy/:id/small
  def small
    media = MediaAttachment.find_by(id: params[:id])
    return head :not_found unless media

    if media.thumbnail.attached?
      redirect_to media.preview_url, allow_other_host: true
    elsif media.file.attached? && media.image?
      redirect_to media.url, allow_other_host: true
    elsif media.remote_url.present?
      redirect_to media.remote_url, allow_other_host: true
    else
      head :not_found
    end
  end
end
