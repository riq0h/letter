# frozen_string_literal: true

# Misskey系から受信した絵文字リアクション(Like/EmojiReactのcontent)を保持する。
# Unicode絵文字はそのまま、カスタム絵文字は :shortcode: 形式(ドメイン部除去・小文字)で格納。
# 通常のふぁぼ(Mastodon系Like)はNULLのまま。
class AddReactionToFavourites < ActiveRecord::Migration[8.0]
  def change
    add_column :favourites, :reaction, :string
  end
end
