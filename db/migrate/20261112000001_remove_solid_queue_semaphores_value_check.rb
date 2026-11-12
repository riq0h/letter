# frozen_string_literal: true

# solid_queue_semaphores.value の独自CHECK制約(value > 0)を外す。
#
# Solid Queueは同時実行制限(limits_concurrency)の残り枠をvalueに記録し、上限1なら
# 最初から0を書き込み、実行中は0まで減らす。この制約はSolid Queue本来のスキーマには無く、
# limits_concurrencyを使うジョブの登録がすべてCHECK違反で失敗していた
# (CacheCleanupJobの毎時実行が登録できなかった)。
class RemoveSolidQueueSemaphoresValueCheck < ActiveRecord::Migration[8.0]
  CONSTRAINT = 'chk_rails_solid_queue_semaphores_on_value'

  def up
    return unless table_exists?(:solid_queue_semaphores)
    return unless check_constraint_exists?(:solid_queue_semaphores, name: CONSTRAINT)

    remove_check_constraint :solid_queue_semaphores, name: CONSTRAINT
  end

  def down
    return unless table_exists?(:solid_queue_semaphores)
    return if check_constraint_exists?(:solid_queue_semaphores, name: CONSTRAINT)

    add_check_constraint :solid_queue_semaphores, 'value > 0', name: CONSTRAINT
  end
end
