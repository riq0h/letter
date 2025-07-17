# frozen_string_literal: true

module BulkEmojiActions
  extend ActiveSupport::Concern

  private

  def process_bulk_emoji_action(action_type, emoji_ids, options = {})
    case action_type
    when 'enable'
      CustomEmoji.where(id: emoji_ids).update_all(disabled: false)
      build_enable_message(emoji_ids, options)
    when 'disable'
      CustomEmoji.where(id: emoji_ids).update_all(disabled: true)
      build_disable_message(emoji_ids, options)
    when 'delete'
      emojis_to_delete = CustomEmoji.where(id: emoji_ids).includes(:image_attachment)
      deleted_count = emojis_to_delete.count
      emojis_to_delete.find_each do |emoji|
        emoji.image.purge if emoji.image.attached?
        emoji.delete
      end
      build_delete_message(deleted_count, options)
    when 'copy'
      process_bulk_emoji_copy_action(emoji_ids)
    else
      { alert: options[:detailed_messages] ? "無効な操作: #{action_type}" : t('custom_emojis.invalid_action') }
    end
  end

  def build_enable_message(emoji_ids, options)
    if options[:detailed_messages]
      { notice: "#{emoji_ids.count}個の絵文字を有効化しました" }
    else
      { notice: t('custom_emojis.bulk_enabled') }
    end
  end

  def build_disable_message(emoji_ids, options)
    if options[:detailed_messages]
      { notice: "#{emoji_ids.count}個の絵文字を無効化しました" }
    else
      { notice: t('custom_emojis.bulk_disabled') }
    end
  end

  def build_delete_message(deleted_count, options)
    if options[:detailed_messages]
      { notice: "#{deleted_count}個の絵文字を削除しました" }
    else
      { notice: t('custom_emojis.bulk_deleted') }
    end
  end

  def process_bulk_emoji_copy_action(emoji_ids, options = {})
    # リモート絵文字のコピー
    remote_emojis = CustomEmoji.remote.where(id: emoji_ids)

    return { alert: '選択された絵文字にリモート絵文字が含まれていません' } if remote_emojis.empty?

    copy_service = RemoteEmojiCopyService.new
    results = copy_service.copy_multiple(remote_emojis.pluck(:id))

    if options[:detailed_copy_messages]
      # ConfigController用の詳細メッセージ
      if results[:success_count].positive?
        message = "#{results[:success_count]}個の絵文字をローカルにコピーしました"
        message += "（#{results[:failed_count]}個は失敗）" if results[:failed_count].positive?
        { notice: message }
      else
        error_details = results[:failed_copies].map { |f| "#{f[:emoji].shortcode}: #{f[:error]}" }.join(', ')
        { alert: "すべての絵文字のコピーに失敗しました: #{error_details}" }
      end
    else
      success_count = results[:success_count]
      failure_count = results[:failed_count]
      total_count = success_count + failure_count

      if failure_count == 0
        { notice: "#{success_count}個の絵文字をコピーしました" }
      elsif success_count.positive?
        { notice: "#{success_count}/#{total_count}個の絵文字をコピーしました（一部失敗）" }
      else
        { alert: '絵文字のコピーに失敗しました' }
      end
    end
  end
end
