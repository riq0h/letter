# frozen_string_literal: true

class ErrorsController < ApplicationController
  def not_found
    respond_to do |format|
      format.json { render json: { error: 'Not Found' }, status: :not_found }
      format.all { render status: :not_found }
    end
  end

  def unprocessable_entity
    respond_to do |format|
      format.json { render json: { error: 'Unprocessable Entity' }, status: :unprocessable_content }
      format.all { render status: :unprocessable_content }
    end
  end

  def internal_server_error
    respond_to do |format|
      format.json { render json: { error: 'Internal Server Error' }, status: :internal_server_error }
      format.all { render status: :internal_server_error }
    end
  end

  # 開発環境でのテスト用（実際の500エラーを発生させる）
  def test_internal_server_error
    return head :not_found unless Rails.env.development?

    raise StandardError, 'Test 500 error for development'
  end
end
