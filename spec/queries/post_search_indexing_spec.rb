# frozen_string_literal: true

require 'rails_helper'

# post_searchトリガーの索引範囲(検索はローカル限定のため、リモート投稿を索引しない)
# rubocop:disable RSpec/DescribeClass -- DBトリガー(スキーマ挙動)のspecで対象クラスが無い
RSpec.describe 'post_search indexing' do
  def post_search_count(object_id)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql(['SELECT COUNT(*) FROM post_search WHERE object_id = ?', object_id])
    )
  end

  it 'indexes local public notes' do
    post = create(:activity_pub_object, :note, actor: create(:actor, local: true),
                                               visibility: 'public', local: true)

    expect(post_search_count(post.id)).to eq(1)
  end

  it 'does not index remote notes (search targets local posts only)' do
    post = create(:activity_pub_object, :note, actor: create(:actor, :remote),
                                               visibility: 'public', local: false,
                                               ap_id: 'https://remote.example.com/notes/1')

    expect(post_search_count(post.id)).to eq(0)
  end

  it 'does not index non-public local notes' do
    post = create(:activity_pub_object, :unlisted, actor: create(:actor, local: true), local: true)

    expect(post_search_count(post.id)).to eq(0)
  end
end
# rubocop:enable RSpec/DescribeClass
