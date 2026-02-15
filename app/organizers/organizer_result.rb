# frozen_string_literal: true

# 全Organizerで共有される結果オブジェクトの基底クラス
# 各OrganizerのResult classはこれを継承し、固有の属性(activity/object/status)を追加する
class OrganizerResult
  attr_reader :success, :error

  def initialize(success:, error: nil)
    @success = success
    @error = error
    freeze
  end

  def success?
    success
  end

  def failure?
    !success
  end
end
