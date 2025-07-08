# frozen_string_literal: true

module StatusEditHandler
  extend ActiveSupport::Concern
  include MediaSerializer

  # 編集履歴用の一時オブジェクト構造体
  TempEditStatus = Struct.new(:content, :summary, :mentions, :tags)
  TempActor = Struct.new(:id, :username, :local?)
  TempMention = Struct.new(:actor, :acct)
  TempTag = Struct.new(:name)

  private

  def build_edit_params
    # Mastodon API poll format: poll[options][] または poll: { options: [] }
    edit_params = params.permit(:status, :spoiler_text, :language, :sensitive,
                                media_ids: [], poll: { options: [] })

    # spoiler_textをsummaryにマッピング（ActivityPubObjectで使用されるフィールド名）
    edit_params[:summary] = edit_params.delete(:spoiler_text) if edit_params.key?(:spoiler_text)

    # contentパラメータをstatusからマッピング
    edit_params[:content] = edit_params.delete(:status) if edit_params.key?(:status)

    # メディアIDの処理
    if edit_params.key?(:media_ids)
      edit_params[:media_ids] = if edit_params[:media_ids].is_a?(Array)
                                  edit_params[:media_ids].compact.compact_blank
                                else
                                  []
                                end
    end

    # 投票パラメータの処理
    edit_params[:poll_options] = if edit_params[:poll].present? && edit_params[:poll][:options].present?
                                   edit_params[:poll][:options].compact.compact_blank
                                 else
                                   []
                                 end
    edit_params.delete(:poll)

    edit_params
  end

  def process_mentions_and_tags_for_edit(edit_params)
    return unless edit_params[:content]

    content = edit_params[:content]
    parsed_content = Content.parse(content)

    # メンションの処理
    if parsed_content.mentions?
      mentions = parsed_content.mentions.pluck(:username).uniq
      edit_params[:mentions] = mentions
    end

    # ハッシュタグの処理
    edit_params[:tags] = parsed_content.hashtags if parsed_content.hashtags?
  end

  def build_current_version
    {
      account: serialized_account(@status.actor),
      content: @status.content || '',
      created_at: (@status.edited_at || @status.published_at).iso8601,
      emojis: extract_emojis_from_status(@status),
      media_attachments: @status.media_attachments.map { |media| serialize_single_media_attachment(media) },
      poll: serialize_poll(@status),
      sensitive: @status.sensitive || false,
      spoiler_text: @status.summary || '',
      tags: @status.tags.map { |tag| serialized_tag(tag) },
      mentions: @status.mentions.map { |mention| serialized_mention(mention) }
    }
  end

  def build_edit_version(edit)
    # 編集時のコンテンツから動的に情報を抽出
    temp_status = build_temp_status_for_edit(edit)

    {
      account: serialized_account(@status.actor),
      content: edit.content || '',
      created_at: edit.created_at.iso8601,
      emojis: serialized_emojis(temp_status),
      media_attachments: edit.media_attachments_data,
      poll: build_poll_from_edit_options(edit),
      sensitive: edit.sensitive || false,
      spoiler_text: edit.summary || '',
      tags: serialized_tags(temp_status),
      mentions: serialized_mentions(temp_status)
    }
  end

  def serialized_media_attachment_from_data(media_data)
    {
      id: media_data['id'],
      type: media_data['type'],
      url: media_data['url'],
      preview_url: media_data['preview_url'],
      description: media_data['description'],
      meta: media_data['meta'] || {}
    }
  end

  def serialized_poll_from_data(poll_data)
    {
      id: poll_data['id'],
      expires_at: poll_data['expires_at'],
      expired: poll_data['expired'] || false,
      multiple: poll_data['multiple'] || false,
      votes_count: poll_data['votes_count'] || 0,
      options: poll_data['options'] || [],
      voted: poll_data['voted'] || false,
      own_votes: poll_data['own_votes'] || []
    }
  end

  def serialized_tag_from_data(tag_data)
    {
      name: tag_data['name'],
      url: tag_data['url']
    }
  end

  def serialized_mention_from_data(mention_data)
    {
      id: mention_data['id'],
      username: mention_data['username'],
      acct: mention_data['acct'],
      url: mention_data['url']
    }
  end

  def extract_emojis_from_status(status)
    # コンテンツと概要からカスタム絵文字を抽出
    text_content = [status.content, status.summary].compact.join(' ')
    emojis = EmojiPresenter.extract_emojis_from(text_content)
    emojis.map(&:to_activitypub)
  rescue StandardError
    []
  end

  # 編集履歴用：既存のシリアライザメソッドを活用するための一時オブジェクト作成
  def build_temp_status_for_edit(edit)
    # コンテンツからメンション・タグを動的に抽出
    mentions_objs = []
    tags_objs = []

    if edit.content.present?
      parsed_content = Content.parse(edit.content)

      # メンション用の簡易オブジェクト作成
      mentions_objs = parsed_content.mentions.map do |mention_data|
        TempMention.new(
          TempActor.new(
            0,
            mention_data[:username],
            mention_data[:domain].nil?
          ),
          mention_data[:acct]
        )
      end

      # タグ用の簡易オブジェクト作成
      tags_objs = parsed_content.hashtags.map { |tag_name| TempTag.new(tag_name) }
    end

    # 既存のserializedメソッドと互換性のある構造を作成
    TempEditStatus.new(
      edit.content,
      edit.summary,
      mentions_objs,
      tags_objs
    )
  end

  def build_poll_from_edit_options(edit)
    return nil if edit.poll_options.blank? || edit.poll_options.empty?

    {
      id: '0',
      expires_at: nil,
      expired: false,
      multiple: false,
      votes_count: 0,
      voters_count: 0,
      options: edit.poll_options.map { |option| { title: option, votes_count: 0 } },
      emojis: [],
      voted: false,
      own_votes: []
    }
  rescue StandardError
    nil
  end
end
