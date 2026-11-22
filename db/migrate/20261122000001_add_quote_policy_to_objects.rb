# frozen_string_literal: true

# 投稿ごとの引用の許可設定(public/followers/nobody)。letterの投稿にだけ使う。
# 未設定(NULL)の投稿は、公開・未収載なら誰でも引用できる
class AddQuotePolicyToObjects < ActiveRecord::Migration[8.0]
  def change
    add_column :objects, :quote_policy, :string
  end
end
