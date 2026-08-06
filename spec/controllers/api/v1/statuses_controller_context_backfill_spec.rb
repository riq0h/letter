# frozen_string_literal: true

require 'rails_helper'

# スレッド表示(context)を契機にしたリプライバックフィル:
# 同期クイックパス(開いた瞬間に反映)+非同期ジョブ(完全化)のハイブリッド
RSpec.describe Api::V1::StatusesController, type: :controller do
  include ActiveJob::TestHelper

  let(:remote_status) do
    create(:activity_pub_object, :note, actor: create(:actor, :remote), local: false,
                                        visibility: 'public', ap_id: 'https://remote.example.com/notes/1')
  end
  let(:job) { instance_double(BackfillRepliesJob, quick_pass: 0) }

  before do
    allow(Rails.cache).to receive(:write).and_return(true)
    # perform_laterは内部でnew(args)を呼ぶため、コントローラが使う引数なしのnewだけを差し替える
    allow(BackfillRepliesJob).to receive(:new).and_call_original
    allow(BackfillRepliesJob).to receive(:new).with(no_args).and_return(job)
  end

  it 'runs the synchronous quick pass and enqueues the full backfill for a remote status' do
    expect do
      get :context, params: { id: remote_status.id }
    end.to have_enqueued_job(BackfillRepliesJob).with(remote_status.id)

    expect(job).to have_received(:quick_pass)
    expect(response).to have_http_status(:ok)
  end

  it 'skips the quick pass when throttled (cache key already present)' do
    allow(Rails.cache).to receive(:write).and_return(false)

    get :context, params: { id: remote_status.id }

    expect(job).not_to have_received(:quick_pass)
    expect(response).to have_http_status(:ok)
  end

  it 'does not backfill local statuses' do
    local = create(:activity_pub_object, :note, actor: create(:actor, local: true))

    expect do
      get :context, params: { id: local.id }
    end.not_to have_enqueued_job(BackfillRepliesJob)

    expect(job).not_to have_received(:quick_pass)
  end
end
