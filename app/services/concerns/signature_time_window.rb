# frozen_string_literal: true

# HTTP署名(draft-cavage / RFC9421 共通)の有効期間判定。規則の形はMastodonと同じで、
# 数値は取りこぼし防止のためMastodonよりやや寛容にしている:
# - 有効期限は expires(署名に含まれる場合)、無ければ作成時刻+10分(Mastodonは5分)。
#   ただし作成時刻+24時間が上限(Mastodonは12時間)
# - 時計のずれとして前後2時間を許容する(Mastodonは1時間)
# 以前は前後5分しか許容しておらず、時計が数分ずれた送信元からの配送を
# 理由を記録しないまま拒否していた。
module SignatureTimeWindow
  DEFAULT_EXPIRATION = 10.minutes
  EXPIRATION_WINDOW_LIMIT = 24.hours
  CLOCK_SKEW_MARGIN = 2.hours

  private

  # created_at / expires_at は Time(またはnil)。理由付きで拒否をログに残す
  def signature_time_window_valid?(created_at, expires_at = nil)
    now = Time.now.utc
    if created_at
      expires_at ||= created_at + DEFAULT_EXPIRATION
      expires_at = [expires_at, created_at + EXPIRATION_WINDOW_LIMIT].min
    end

    if created_at && created_at > now + CLOCK_SKEW_MARGIN
      Rails.logger.warn "🔐 Signature rejected: created #{(created_at - now).round}s in the future"
      return false
    end
    if expires_at && now > expires_at + CLOCK_SKEW_MARGIN
      Rails.logger.warn "🔐 Signature rejected: expired #{(now - expires_at).round}s ago"
      return false
    end

    true
  end
end
