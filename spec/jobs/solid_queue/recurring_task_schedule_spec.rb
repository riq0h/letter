# frozen_string_literal: true

require 'rails_helper'

# config/recurring.yml の本番定期タスク
RSpec.describe SolidQueue::RecurringTask do
  let(:tasks) { YAML.load_file(Rails.root.join('config/recurring.yml'), aliases: true).fetch('production') }

  def fire_times(schedule, from:, to:)
    cron = Fugit.parse(schedule, multi: :fail)
    times = []
    time = from
    while (time = cron.next_time(time).to_t) <= to
      times << time
    end
    times
  end

  it 'defines only valid tasks' do
    tasks.each do |key, options|
      task = described_class.from_configuration(key, **options.symbolize_keys)

      expect(task).to be_valid, "#{key}: #{task.errors.full_messages.join(', ')}"
    end
  end

  # 同時に登録するとqueue DBへの書き込みが競合し得る
  it 'never enqueues two tasks at the same moment' do
    from = Time.zone.local(2026, 1, 1)
    all_times = tasks.values.flat_map { |options| fire_times(options['schedule'], from: from, to: from + 2.days).uniq }

    expect(all_times.size).to eq(all_times.uniq.size)
  end

  it 'clears finished jobs older than a day and keeps the rest' do
    base = { queue_name: 'default', class_name: 'ExampleJob', arguments: '[]', priority: 0 }
    SolidQueue::Job.insert_all([
                                 base.merge(active_job_id: 'old', finished_at: 2.days.ago),
                                 base.merge(active_job_id: 'recent', finished_at: 1.hour.ago),
                                 base.merge(active_job_id: 'unfinished', finished_at: nil)
                               ])

    SolidQueue::RecurringJob.perform_now(tasks.dig('clear_solid_queue_finished_jobs', 'command'))

    expect(SolidQueue::Job.where(active_job_id: %w[old recent unfinished]).pluck(:active_job_id))
      .to contain_exactly('recent', 'unfinished')
  end
end
