# frozen_string_literal: true

class SessionsController < ApplicationController
  before_action :redirect_if_signed_in, only: %i[new create]

  # GET /login
  def new
    # ログインフォーム表示
  end

  # POST /login
  def create
    actor = find_local_actor

    if actor
      auth_result = actor.authenticate(params[:password])

      if auth_result
        login_success(actor)
      else
        login_failure
      end
    else
      login_failure
    end
  end

  # DELETE /logout
  def destroy
    logout_user
    redirect_to root_path, notice: I18n.t('auth.logged_out')
  end

  private

  def find_local_actor
    username = params[:username]&.strip
    return nil if username.blank?

    Actor.local.where('LOWER(username) = LOWER(?)', username).first
  end

  def login_success(actor)
    login_user(actor)
    redirect_to_after_login
  end

  def login_failure
    Rails.logger.warn "⚠️ Login failure: username=#{params[:username]&.strip.inspect} ip=#{request.remote_ip}"
    flash.now[:alert] = I18n.t('auth.invalid_credentials')
    render :new, status: :unprocessable_entity
  end

  def login_user(actor)
    reset_session
    session[:current_user_id] = actor.id
    session[:logged_in_at] = Time.current
  end

  def logout_user
    reset_session
  end

  def redirect_to_after_login
    redirect_url = session.delete(:return_to) || config_path
    redirect_to redirect_url, notice: I18n.t('auth.logged_in')
  end

  def redirect_if_signed_in
    redirect_to config_path if user_signed_in?
  end
end
