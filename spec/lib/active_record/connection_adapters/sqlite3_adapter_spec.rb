# frozen_string_literal: true

require 'rails_helper'

# config/database.yml の設定が、SQLiteの接続に実際に反映されること
RSpec.describe ActiveRecord::ConnectionAdapters::SQLite3Adapter do
  let(:path) { Rails.root.join('tmp', "sqlite_adapter_#{SecureRandom.hex(4)}.sqlite3").to_s }
  let(:connections) { [] }

  after do
    connections.each(&:disconnect!)
    FileUtils.rm_f(Dir.glob("#{path}*"))
  end

  def open_connection(config)
    described_class.new(config.merge(adapter: 'sqlite3', database: path)).tap { |connection| connections << connection }
  end

  def production_config(name)
    ActiveRecord::Base.configurations.configs_for(env_name: 'production', name: name).configuration_hash
  end

  it 'keeps the thread holding the write lock running while another thread in the process waits for the lock' do
    holder = open_connection(production_config('primary'))
    waiter = open_connection(production_config('primary'))
    holder.execute('CREATE TABLE items (value INTEGER)')
    locked = Queue.new

    writing = Thread.new do
      holder.transaction do
        holder.execute('INSERT INTO items VALUES (1)')
        locked << true
        sleep 0.2
      end
    end
    locked.pop

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    waiter.execute('INSERT INTO items VALUES (2)')
    waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    writing.join

    expect(waited).to be < 2
    expect(waiter.select_value('SELECT COUNT(*) FROM items')).to eq(2)
  end

  %w[primary queue cache].each do |name|
    it "applies the SQLite settings written for the #{name} database in production" do
      pragmas = production_config(name).fetch(:pragmas).stringify_keys
      connection = open_connection(production_config(name))

      expect(connection.select_value('PRAGMA cache_size')).to eq(pragmas.fetch('cache_size'))
      expect(connection.select_value('PRAGMA wal_autocheckpoint')).to eq(pragmas.fetch('wal_autocheckpoint'))
      expect(connection.select_value('PRAGMA foreign_keys')).to eq(1)
    end
  end
end
