# frozen_string_literal: true

module ActivityPubHelper
  # 投稿・アクターなど名義が問題になる文書の取得。idと取得元の一致を検証する
  def fetch_activitypub_object(uri)
    ActivityPubHttpClient.fetch_verified(uri)
  end
end
