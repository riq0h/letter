# frozen_string_literal: true

# 投稿を誰が引用できるか。Mastodon 4.5のAPIが返すquote_approvalと、連合に出す
# interactionPolicy.canQuote(FEP-044f)の両方をここで決める。
#
# letterの投稿は投稿ごとの設定(誰でも・フォロワーのみ・自分のみ)に従う。フォロワー限定と
# DMの投稿は、設定にかかわらず自分のみ(DMは自分も引用できない)。
# 他サーバの投稿は、相手が投稿に示すinteractionPolicyに従う。示していないサーバ(Misskeyや
# 4.5より前のMastodonなど)の公開・未収載の投稿は、誰でも引用できるものとして扱う
class QuotePolicy
  SETTINGS = %w[public followers nobody].freeze
  DEFAULT_SETTING = 'public'
  QUOTABLE_VISIBILITIES = %w[public unlisted].freeze
  PUBLIC_COLLECTION = 'https://www.w3.org/ns/activitystreams#Public'
  PUBLIC_ALIASES = [PUBLIC_COLLECTION, 'as:Public', 'Public'].freeze
  # GoToSocialの古い形式(always/approvalRequired)も読む
  AUTOMATIC_KEYS = %w[automaticApproval always].freeze
  MANUAL_KEYS = %w[manualApproval approvalRequired].freeze

  # 投稿に保存する設定。フォロワー限定・DMは常にnobody、指定がない・不正なら既定値
  def self.setting_for(visibility, requested)
    return 'nobody' unless QUOTABLE_VISIBILITIES.include?(visibility)

    SETTINGS.include?(requested) ? requested : DEFAULT_SETTING
  end

  def initialize(status)
    @status = status
    @author = status.actor
  end

  # 自動で承認される相手(public/followers/following/unsupported_policy)
  def automatic
    return local_categories if @author.local?
    return [] unless QUOTABLE_VISIBILITIES.include?(@status.visibility)
    return ['public'] unless declared?

    categorize(approval_uris(AUTOMATIC_KEYS))
  end

  # 作者が手動で承認する相手。letterは手動承認を持たない
  def manual
    return [] if @author.local? || !declared? || QUOTABLE_VISIBILITIES.exclude?(@status.visibility)

    categorize(approval_uris(MANUAL_KEYS))
  end

  # actorが引用したときにどうなるか: automatic / manual / denied / unknown
  def for(actor)
    return 'unknown' if actor.nil?
    return 'denied' if @status.visibility == 'direct'
    return 'automatic' if actor.id == @author.id
    return 'denied' unless QUOTABLE_VISIBILITIES.include?(@status.visibility)

    @author.local? ? local_decision(actor) : remote_decision(actor)
  end

  # 作者が引用を許さないとわかっている場合だけfalse(unknownは相手サーバの判断に任せる)
  def allows?(actor)
    self.for(actor) != 'denied'
  end

  # 他サーバの投稿が引用の許可設定を示しているか(示すサーバは承認の仕組みを持つ)
  def declared?
    can_quote.is_a?(Hash)
  end

  # letterの投稿として連合に出すinteractionPolicy
  def to_interaction_policy
    uris = case local_setting
           when 'public' then [PUBLIC_COLLECTION]
           when 'followers' then [@author.followers_url]
           else [@author.ap_id]
           end
    { 'canQuote' => { 'automaticApproval' => uris } }
  end

  private

  def local_setting
    self.class.setting_for(@status.visibility, @status.quote_policy)
  end

  def local_categories
    case local_setting
    when 'public' then ['public']
    when 'followers' then ['followers']
    else []
    end
  end

  def local_decision(actor)
    return 'denied' if blocked?(actor)

    case local_setting
    when 'public' then 'automatic'
    when 'followers' then follows?(actor, @author) ? 'automatic' : 'denied'
    else 'denied'
    end
  end

  def remote_decision(actor)
    return 'automatic' unless declared?

    automatic_uris = approval_uris(AUTOMATIC_KEYS)
    manual_uris = approval_uris(MANUAL_KEYS)
    return 'automatic' if covers?(automatic_uris, actor)
    return 'manual' if covers?(manual_uris, actor)
    return 'unknown' if categorize(automatic_uris + manual_uris).include?('unsupported_policy')

    'denied'
  end

  def covers?(uris, actor)
    uris.any? do |uri|
      PUBLIC_ALIASES.include?(uri) || uri == actor.ap_id ||
        (uri == @author.followers_url && follows?(actor, @author)) ||
        (uri == @author.following_url && follows?(@author, actor))
    end
  end

  def categorize(uris)
    uris.filter_map { |uri| category(uri) }.uniq
  end

  def category(uri)
    return 'public' if PUBLIC_ALIASES.include?(uri)
    return 'followers' if uri == @author.followers_url
    return 'following' if uri == @author.following_url
    return if uri == @author.ap_id

    'unsupported_policy'
  end

  def approval_uris(keys)
    keys.flat_map { |key| Array.wrap(can_quote[key]) }
        .filter_map { |entry| entry.is_a?(Hash) ? entry['id'] : entry }
        .map(&:to_s)
  end

  def can_quote
    return @can_quote if defined?(@can_quote)

    data = @status.raw_data.is_a?(String) ? JSON.parse(@status.raw_data) : @status.raw_data
    policy = data['interactionPolicy'] if data.is_a?(Hash)
    @can_quote = policy.is_a?(Hash) ? policy['canQuote'] : nil
  rescue JSON::ParserError
    @can_quote = nil
  end

  def follows?(follower, followed)
    follower.follows.accepted.exists?(target_actor: followed)
  end

  def blocked?(actor)
    @author.blocking?(actor) || @author.domain_blocking?(actor.domain)
  end
end
