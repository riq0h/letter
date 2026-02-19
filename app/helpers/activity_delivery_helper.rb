# frozen_string_literal: true

# SendActivityJobのトランザクション安全な登録ヘルパー
#
# ActiveRecordトランザクション内でSendActivityJob.perform_laterを呼ぶと、
# Activityレコードがコミットされる前にジョブが実行され、
# RecordNotFoundで破棄される競合状態が発生する。
#
# このヘルパーはジョブ登録をトランザクションのコミット後まで遅延させる。
module ActivityDeliveryHelper
  def enqueue_send_activity(activity, inbox_urls)
    return if inbox_urls.blank?

    activity_id = activity.id
    connection = ActiveRecord::Base.connection

    if connection.transaction_open?
      connection.current_transaction.after_commit do
        SendActivityJob.perform_later(activity_id, inbox_urls)
      end
    else
      SendActivityJob.perform_later(activity_id, inbox_urls)
    end
  end
end
