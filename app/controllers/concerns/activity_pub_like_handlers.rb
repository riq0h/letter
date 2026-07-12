# frozen_string_literal: true

module ActivityPubLikeHandlers
  extend ActiveSupport::Concern
  include EmojiTagProcessing

  private

  # Like / EmojiReact Activity処理
  # Misskey系はLikeのcontent(例 ":igyo@.:" や絵文字)、Pleroma系はEmojiReactで
  # 絵文字リアクションを送ってくる。ふぁぼとして数えつつ、絵文字はreactionに保持する。
  def handle_like_activity
    Rails.logger.info "❤️ Processing #{@activity['type']} activity"

    object_ap_id = extract_like_object_id
    return head(:accepted) unless object_ap_id

    # ローカルに存在する投稿のみ処理（他人の投稿へのLikeはスキップ）
    target_object = ActivityPubObject.find_by(ap_id: object_ap_id)
    return head(:accepted) unless target_object

    create_or_update_like(target_object)
    head :accepted
  end

  def extract_like_object_id
    extract_activity_object_id(@activity['object'])
  end

  def create_or_update_like(target_object)
    # 自分の投稿へのLikeのみフル保存（通知を維持するため）
    # 他人の投稿へのLikeはスキップ（参照時にリモートから取得）
    return unless target_object.actor.local?

    reaction = extract_reaction_content

    # リアクションのカスタム絵文字(tag内Emoji)を取り込む。表示用の画像は
    # after_create_commitの先読みでR2にキャッシュされる
    process_emoji_tags(@activity['tag'], domain: @sender.domain) if reaction

    if like_already_exists?(target_object)
      backfill_reaction(target_object, reaction)
      return
    end

    create_new_like(target_object, reaction)
  end

  # Misskey/Pleroma系のリアクション絵文字を正規化して返す(なければnil)
  # カスタム絵文字 ":name@domain:" / ":name@.:" は ":name:"(小文字)に統一。
  # ドメインは送信者(favourites.actor.domain)から復元できるため保持しない。
  def extract_reaction_content
    raw = @activity['content'].presence || @activity['_misskey_reaction'].presence
    return nil if raw.blank?

    raw = raw.strip
    if (m = raw.match(/\A:([a-zA-Z0-9_-]+)(?:@[^:\s]*)?:\z/))
      ":#{m[1].downcase}:"
    else
      # 旧Misskeyの名前付きリアクション(star等)はUnicode絵文字に変換して保存する
      Favourite::LEGACY_MISSKEY_REACTIONS[raw] || raw[0, 64] # Unicode絵文字(念のため長さ上限)
    end
  end

  # 既存ふぁぼがプレーン(reaction無し)で、後からリアクションが届いた場合は絵文字だけ補完する
  def backfill_reaction(target_object, reaction)
    return if reaction.blank?

    favourite = find_existing_favourite(target_object)
    return unless favourite && favourite.reaction.blank?

    favourite.update!(reaction: reaction)
    Rails.logger.info "❤️ Reaction backfilled on favourite #{favourite.id}: #{reaction}"
  end

  def like_already_exists?(target_object)
    existing_activity = find_existing_like_activity(target_object)
    existing_favourite = find_existing_favourite(target_object)

    if existing_activity || existing_favourite
      Rails.logger.info "❤️ Like already exists: Activity #{existing_activity&.id}, Favourite #{existing_favourite&.id}"
      return true
    end

    false
  end

  def find_existing_like_activity(target_object)
    target_object.activities.find_by(actor: @sender, activity_type: 'Like')
  end

  def find_existing_favourite(target_object)
    Favourite.find_by(actor: @sender, object: target_object)
  end

  def create_new_like(target_object, reaction = nil)
    ActiveRecord::Base.transaction do
      like_activity = create_like_activity_record(target_object)
      favourite = create_favourite_record(target_object, reaction)

      log_like_creation(like_activity, favourite, target_object)
    end
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info '❤️ Like already exists (concurrent request)'
  end

  def create_like_activity_record(target_object)
    # EmojiReactもactivity_type='Like'で保存する(Undo解決・カウントを共通化するため)
    target_object.activities.create!(
      actor: @sender,
      activity_type: 'Like',
      ap_id: @activity['id'],
      target_ap_id: target_object.ap_id,
      published_at: Time.current,
      local: false,
      processed: true
    )
  end

  def create_favourite_record(target_object, reaction = nil)
    Favourite.create!(
      actor: @sender,
      object: target_object,
      ap_id: @activity['id'],
      reaction: reaction
    )
  end

  def log_like_creation(like_activity, favourite, target_object)
    Rails.logger.info "❤️ Like created: Activity #{like_activity.id}, Favourite #{favourite.id}, " \
                      "favourites_count updated to #{target_object.reload.favourites_count}"
  end
end
