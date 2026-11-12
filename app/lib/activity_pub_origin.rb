# frozen_string_literal: true

# ActivityPubの識別子(URI)の出所を照合するための小さなヘルパ。
# 他サーバの名義をかたる文書を取り込まないよう、Mastodonと同じく
# 「文書のid・作者・取得元が同じホストか」で判定する。
module ActivityPubOrigin
  module_function

  # 値がURI文字列ならそのまま、{ 'id' => ... } ならそのidを、配列なら先頭要素について返す
  def value_or_id(value)
    case value
    when String then value
    when Hash then value['id'].is_a?(String) ? value['id'] : nil
    when Array then value_or_id(value.first)
    end
  end

  def host_of(uri)
    return nil unless uri.is_a?(String)

    URI.parse(uri).host&.downcase
  rescue URI::InvalidURIError
    nil
  end

  # 2つのURIのホストが一致するか(どちらかが解釈できなければ不一致)
  def same_host?(uri_a, uri_b)
    host_a = host_of(uri_a)
    host_a.present? && host_a == host_of(uri_b)
  end
end
