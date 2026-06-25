# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DatabaseLockRetryable do
  let(:klass) do
    Class.new do
      include DatabaseLockRetryable

      # privateメソッドをテストから呼べるよう公開ラッパを用意
      def run(max_retries: DatabaseLockRetryable::MAX_LOCK_RETRIES, &)
        with_database_lock_retry(max_retries: max_retries, &)
      end
    end
  end
  let(:instance) { klass.new }

  before { allow(instance).to receive(:sleep) } # バックオフ待機を無効化

  def locked_error
    ActiveRecord::StatementInvalid.new('SQLite3::BusyException: database is locked')
  end

  it 'returns the block result when no error occurs' do
    expect(instance.run { 42 }).to eq(42)
  end

  it 'retries on "database is locked" and succeeds on a later attempt' do
    attempts = 0
    result = instance.run do
      attempts += 1
      raise locked_error if attempts < 3

      :ok
    end
    expect(attempts).to eq(3)
    expect(result).to eq(:ok)
  end

  it 'gives up and re-raises after exhausting retries' do
    attempts = 0
    expect do
      instance.run(max_retries: 2) do
        attempts += 1
        raise locked_error
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(attempts).to eq(3) # 初回 + リトライ2回
  end

  it 'does not retry on unrelated StatementInvalid errors' do
    attempts = 0
    expect do
      instance.run do
        attempts += 1
        raise ActiveRecord::StatementInvalid, 'no such column: foo'
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /no such column/)
    expect(attempts).to eq(1)
  end
end
