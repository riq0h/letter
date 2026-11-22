# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/persistent_logger')

RSpec.describe PersistentLogger do
  let(:stdout) { StringIO.new }
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, 'production.log') }
  let(:logger) { described_class.build(stdout, path, generations: 2, size: 1024 * 1024) }

  after { FileUtils.remove_entry(dir) }

  it 'runs a tagged block only once' do
    runs = 0
    logger.tagged('job') { runs += 1 }

    expect(runs).to eq(1)
  end

  it 'writes the same tagged lines to standard output and the file, with time and severity in the file' do
    logger.tagged('request-1') { logger.info('hello') }

    expect(stdout.string).to eq("[request-1] hello\n")
    expect(File.read(path)).to match(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z INFO \[request-1\] hello$/)
  end

  it 'lets jobs be enqueued and performed with their tags' do
    job_class = Class.new(ApplicationJob) do
      def self.name = 'LoggedJob'
      def perform = logger.info('working')
    end
    job_class.logger = logger

    expect { job_class.perform_later }.not_to raise_error
    job_class.perform_now

    expect(File.read(path)).to match(/\[ActiveJob\] \[LoggedJob\] \[[0-9a-f-]+\] working$/)
  end

  it 'keeps the tags pushed for a request in both outputs' do
    tags = logger.push_tags('request-2')
    logger.info('pushed')
    logger.pop_tags(tags.size)
    logger.info('after')

    expect(tags).to eq(['request-2'])
    expect(File.read(path)).to include('[request-2] pushed')
    expect(File.read(path)).not_to include('[request-2] after')
  end
end
