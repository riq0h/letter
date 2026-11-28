# frozen_string_literal: true

# ストリーミングで配信する出来事の受け渡し場所。出来事はWebプロセスでもジョブのプロセスでも起き、
# 接続はPumaの各プロセスが持つので、プロセスをまたいで渡す。プライマリDBの書き込みと
# ロックを取り合わないよう、キャッシュDBに置く
class CreateStreamingEvents < ActiveRecord::Migration[8.0]
  def change
    return unless ActiveRecord::Base.connection_db_config.name == 'cache'

    create_table :streaming_events do |t|
      t.string :kind, null: false
      t.string :target_id, null: false
      t.integer :recipient_id
      t.boolean :public_visibility, null: false, default: false
      t.datetime :created_at, null: false
    end

    add_index :streaming_events, :created_at, name: 'idx_streaming_events_created_at'
  end
end
