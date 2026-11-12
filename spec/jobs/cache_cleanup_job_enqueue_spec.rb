# frozen_string_literal: true

require 'rails_helper'

# 同時実行制限(limits_concurrency to: 1)を使うジョブは、Solid Queueが残り枠0の
# セマフォを書き込めないと登録できない
RSpec.describe CacheCleanupJob do
  it 'allows Solid Queue to record a semaphore with no remaining slots' do
    semaphore = SolidQueue::Semaphore.create!(key: 'cache_cleanup', value: 0, expires_at: 2.hours.from_now)

    expect(semaphore).to be_persisted
  end
end
