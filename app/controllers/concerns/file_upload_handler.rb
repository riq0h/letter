# frozen_string_literal: true

module FileUploadHandler
  extend ActiveSupport::Concern

  private

  def process_file_uploads
    handle_avatar_upload_active_storage if params[:avatar]
    handle_header_upload_active_storage if params[:header]
  end

  def handle_avatar_upload_active_storage
    return unless valid_upload?(params[:avatar])

    # ActorImageProcessorを使用して画像処理とプロフィール更新通知を実行
    current_user.attach_avatar_with_folder(
      io: params[:avatar].tempfile,
      filename: params[:avatar].original_filename,
      content_type: params[:avatar].content_type
    )
    Rails.logger.info "Avatar uploaded for #{current_user.username} via ActorImageProcessor"
  end

  def handle_header_upload_active_storage
    return unless valid_upload?(params[:header])

    # ActorImageProcessorのheader版メソッドを使用して画像処理とプロフィール更新通知を実行
    processor = ActorImageProcessor.new(current_user)
    processor.attach_header_with_folder(
      io: params[:header].tempfile,
      filename: params[:header].original_filename,
      content_type: params[:header].content_type
    )
    Rails.logger.info "Header uploaded for #{current_user.username} via ActorImageProcessor"
  end

  def valid_upload?(file)
    return false unless file.respond_to?(:content_type)

    allowed_types = %w[image/jpeg image/jpg image/png image/gif image/webp]
    max_size = 5.megabytes

    # Marcel gemを使って実際のファイル内容からMIMEタイプを判定
    actual_type = Marcel::MimeType.for(file)
    unless allowed_types.include?(actual_type)
      Rails.logger.warn "Unsupported file type: #{actual_type}"
      return false
    end

    if file.size > max_size
      Rails.logger.warn "File too large: #{file.size} bytes"
      return false
    end

    true
  end

  def update_account_attributes
    update_params = account_params.except(:avatar, :header, :fields_attributes)

    # fields_attributesをfieldsに変換
    if params.key?(:fields_attributes)
      mapped_fields = params[:fields_attributes].values.map do |field|
        {
          'name' => field[:name].to_s.strip,
          'value' => field[:value].to_s.strip
        }
      end
      fields = mapped_fields.select { |field| field['name'].present? || field['value'].present? }
      update_params[:fields] = fields.to_json
    end

    if current_user.update(update_params)
      render json: serialized_account(current_user, is_self: true)
    else
      render_account_update_errors
    end
  end

  def render_account_update_errors
    errors = current_user.errors.full_messages
    Rails.logger.error "Account update failed: #{errors}"
    render_validation_failed_with_details('Update failed', errors)
  end
end
