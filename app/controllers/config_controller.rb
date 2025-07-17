# frozen_string_literal: true

class ConfigController < ApplicationController
  include BulkEmojiActions
  include ConfigBuilder
  include EmojiFiltering
  before_action :authenticate_user!

  # GET /config
  def show
    @config = current_instance_config
  end

  # PATCH /config
  def update
    if update_instance_config && update_user_profile
      redirect_to config_path, notice: I18n.t('config.updated')
    else
      @config = current_instance_config
      flash.now[:alert] = I18n.t('config.update_failed')
      render :show, status: :unprocessable_entity
    end
  end

  # GET /config/custom_emojis
  def custom_emojis
    @tab = params[:tab] || 'local'
    @custom_emojis = base_emoji_scope_for_tab(@tab)
    @custom_emojis = apply_emoji_filters(@custom_emojis)

    # リモートドメインの統計情報
    return unless @tab == 'remote'

    @remote_domains = CustomEmoji.remote.group(:domain).count
  end

  # GET /config/relays
  def relays
    @relays = Relay.all
  end

  # GET /config/custom_emojis/new
  def new_custom_emoji
    @custom_emoji = CustomEmoji.new
  end

  # POST /config/custom_emojis
  def create_custom_emoji
    @custom_emoji = CustomEmoji.new(custom_emoji_params)

    if @custom_emoji.save
      redirect_to config_custom_emojis_path, notice: t('custom_emojis.created')
    else
      render :new_custom_emoji, status: :unprocessable_entity
    end
  end

  # GET /config/custom_emojis/:id/edit
  def edit_custom_emoji
    @custom_emoji = CustomEmoji.find(params[:id])
  end

  # PATCH /config/custom_emojis/:id
  def update_custom_emoji
    @custom_emoji = CustomEmoji.find(params[:id])

    if @custom_emoji.update(custom_emoji_params)
      redirect_to config_custom_emojis_path, notice: t('custom_emojis.updated')
    else
      render :edit_custom_emoji, status: :unprocessable_entity
    end
  end

  # DELETE /config/custom_emojis/:id
  def destroy_custom_emoji
    @custom_emoji = CustomEmoji.find(params[:id])
    @custom_emoji.destroy
    redirect_to config_custom_emojis_path, notice: t('custom_emojis.deleted')
  end

  # PATCH /config/custom_emojis/:id/enable
  def enable_custom_emoji
    @custom_emoji = CustomEmoji.find(params[:id])
    @custom_emoji.update(disabled: false)
    redirect_to config_custom_emojis_path, notice: t('custom_emojis.enabled')
  end

  # PATCH /config/custom_emojis/:id/disable
  def disable_custom_emoji
    @custom_emoji = CustomEmoji.find(params[:id])
    @custom_emoji.update(disabled: true)
    redirect_to config_custom_emojis_path, notice: t('custom_emojis.disabled')
  end

  # POST /config/custom_emojis/bulk_action
  def bulk_action_custom_emojis
    emoji_ids = params[:emoji_ids]&.reject(&:blank?)
    action_type = params[:action_type]

    if emoji_ids.blank?
      redirect_to config_custom_emojis_path(tab: params[:tab]), alert: t('custom_emojis.no_selection')
      return
    end

    result = process_bulk_emoji_action(action_type, emoji_ids, detailed_messages: true, detailed_copy_messages: true)
    redirect_to config_custom_emojis_path(tab: params[:tab]), result
  end

  # POST /config/custom_emojis/copy_remote
  def copy_remote_emojis
    emoji_ids = params[:emoji_ids]&.reject(&:blank?)

    if emoji_ids.blank?
      redirect_to config_custom_emojis_path(tab: 'remote'), alert: t('custom_emojis.copy_no_selection')
      return
    end

    copy_service = RemoteEmojiCopyService.new
    results = copy_service.copy_multiple(emoji_ids)

    if results[:success_count].positive?
      message = "#{results[:success_count]}個の絵文字をローカルにコピーしました"
      message += "（#{results[:failed_count]}個は失敗）" if results[:failed_count].positive?
      redirect_to config_custom_emojis_path(tab: 'local'), notice: message
    else
      error_details = results[:failed_copies].map { |f| "#{f[:emoji].shortcode}: #{f[:error]}" }.join(', ')
      redirect_to config_custom_emojis_path(tab: 'remote'), alert: "すべての絵文字のコピーに失敗しました: #{error_details}"
    end
  end

  # POST /config/custom_emojis/discover_remote
  def discover_remote_emojis
    domain = params[:domain]&.strip

    if domain.present?
      # 特定ドメインからの発見
      RemoteEmojiDiscoveryJob.perform_later(domain)
      redirect_to config_custom_emojis_path(tab: 'remote'), notice: "#{domain} からの絵文字発見を開始しました"
    else
      # 全ドメインからの発見
      RemoteEmojiDiscoveryJob.perform_later
      redirect_to config_custom_emojis_path(tab: 'remote'), notice: t('custom_emojis.discovery_started')
    end
  end

  # === Relay Management Actions ===

  # POST /config/relays
  def create_relay
    inbox_url = params[:inbox_url]&.strip

    if inbox_url.blank?
      redirect_to config_relays_path, alert: t('relays.url_required')
      return
    end

    relay = Relay.new(inbox_url: inbox_url, state: 'idle')

    if relay.save
      redirect_to config_relays_path, notice: t('relays.added')
    else
      redirect_to config_relays_path, alert: "リレーの追加に失敗しました: #{relay.errors.full_messages.join(', ')}"
    end
  end

  # PATCH /config/relays/:id
  def update_relay
    relay = Relay.find(params[:id])
    action = params[:action_type] || params[:relay]&.dig(:action)

    case action
    when 'enable'
      enable_relay(relay)
    when 'disable'
      disable_relay(relay)
    else
      redirect_to config_relays_path, alert: t('relays.invalid_action')
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to config_relays_path, alert: t('relays.not_found')
  end

  # DELETE /config/relays/:id
  def destroy_relay
    relay = Relay.find(params[:id])

    # 接続済みの場合は先に切断
    if relay.accepted?
      unfollow_service = RelayUnfollowService.new
      unfollow_service.call(relay)
    end

    if relay.destroy
      redirect_to config_relays_path, notice: t('relays.deleted')
    else
      redirect_to config_relays_path, alert: t('relays.delete_failed')
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to config_relays_path, alert: t('relays.not_found')
  end

  private

  def update_instance_config
    params = config_params
    return false if params.nil?

    save_config(params)
    true
  rescue StandardError => e
    Rails.logger.error "Config update failed: #{e.message}"
    false
  end

  def update_user_profile
    return true if params[:actor].blank?

    actor_params = params.expect(actor: [:note, :avatar, :header, :display_name, { fields: %i[name value] }])

    # fieldsパラメータの再構成（配列形式からハッシュの配列へ）
    if params[:actor][:fields].present?
      fields_array = []
      params[:actor][:fields].each do |field|
        fields_array << { name: field[:name], value: field[:value] } if field[:name].present? || field[:value].present?
      end
      actor_params[:fields] = fields_array.to_json if fields_array.any?
    end

    # アバター画像の処理
    if actor_params[:avatar].present?
      process_avatar_upload(actor_params[:avatar])
      actor_params.delete(:avatar)
    end

    # ヘッダー画像の処理（通常のアップロード）
    header_file = actor_params.delete(:header) if actor_params[:header].present?

    result = current_user.update(actor_params)

    # ヘッダー画像を通常通りアップロード
    current_user.header.attach(header_file) if header_file.present?

    result
  rescue StandardError => e
    Rails.logger.error "User profile update failed: #{e.message}"
    false
  end

  def process_avatar_upload(uploaded_file)
    processor = ActorImageProcessor.new(current_user)
    processor.attach_avatar_with_folder(
      io: uploaded_file,
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type
    )
  end

  def save_config(new_config)
    config_file = Rails.root.join('config', 'instance_config.yml')
    current_config = build_stored_config_hash

    updated_config = merge_configs(current_config, new_config)
    write_config_file(config_file, updated_config)
  end

  def merge_configs(current_config, new_config)
    current_config.merge(new_config.compact)
  end

  def write_config_file(config_file, updated_config)
    File.write(config_file, updated_config.to_yaml)
  end

  def config_params
    return nil unless params[:config]

    params.expect(
      config: %i[instance_name
                 instance_description
                 instance_contact_email
                 instance_maintainer
                 blog_footer
                 background_color]
    )
  end

  def current_instance_config
    build_base_config
  end

  def base_emoji_scope
    CustomEmoji.includes(:image_attachment).order(created_at: :desc)
  end

  def custom_emoji_params
    params.expect(custom_emoji: %i[shortcode domain image disabled visible_in_picker])
  end

  def enable_relay(relay)
    if relay.idle?
      # ActivityPub Follow アクティビティを送信
      follow_service = RelayFollowService.new
      success = follow_service.call(relay)

      if success
        redirect_to config_relays_path, notice: t('relays.connection_started')
      else
        redirect_to config_relays_path, alert: "リレーへの接続に失敗しました: #{relay.last_error}"
      end
    else
      redirect_to config_relays_path, alert: t('relays.already_processing')
    end
  end

  def disable_relay(relay)
    if relay.accepted?
      # ActivityPub Undo Follow アクティビティを送信
      unfollow_service = RelayUnfollowService.new
      success = unfollow_service.call(relay)

      if success
        redirect_to config_relays_path, notice: t('relays.disconnected')
      else
        redirect_to config_relays_path, alert: "リレーからの切断に失敗しました: #{relay.last_error}"
      end
    else
      relay.update!(state: 'idle')
      redirect_to config_relays_path, notice: t('relays.reset')
    end
  end
end
