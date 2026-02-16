# frozen_string_literal: true

class ErrorsController < ApplicationController
  def not_found
    render status: :not_found
  end

  def unprocessable_entity
    render status: :unprocessable_content
  end

  def internal_server_error
    render status: :internal_server_error
  end

  # 開発環境でのテスト用（実際の500エラーを発生させる）
  def test_internal_server_error
    return head :not_found unless Rails.env.development?

    raise StandardError, 'Test 500 error for development'
  end
end
