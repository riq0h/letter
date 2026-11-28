# frozen_string_literal: true

require 'rails_helper'

# 転送されたUpdate/Deleteは本文を使わず、元のサーバで投稿の今の状態を確かめて反映する
RSpec.describe ApplyForwardedChangeJob do
  let(:author) { create(:actor, :remote, domain: 'origin.example', ap_id: 'https://origin.example/users/alice') }
  let!(:status) do
    create(:activity_pub_object, :remote, actor: author, ap_id: 'https://origin.example/notes/1', content: '<p>before</p>')
  end
  let(:client) { ActivityPubHttpClient.new }

  before do
    create(:actor)
    allow(ActivityPubHttpClient).to receive(:new).and_return(client)
    allow(client).to receive(:validate_url_for_ssrf!).and_return(true)
  end

  def origin_answers(code, body = {})
    response = instance_double(HTTParty::Response, code: code, success?: (200..299).cover?(code), body: body.to_json,
                                                   headers: { 'content-type' => 'application/activity+json' })
    allow(HTTParty).to receive(:get).with(status.ap_id, anything).and_return(response)
  end

  def note(content, author_uri: author.ap_id)
    { 'id' => status.ap_id, 'type' => 'Note', 'attributedTo' => author_uri, 'content' => content,
      'updated' => Time.current.iso8601, 'to' => ['https://www.w3.org/ns/activitystreams#Public'] }
  end

  describe 'a forwarded Delete' do
    [404, 410].each do |code|
      it "deletes the post when its origin answers #{code}" do
        origin_answers(code)

        described_class.perform_now('Delete', status.ap_id, author.ap_id)

        expect(ActivityPubObject.exists?(status.id)).to be(false)
      end
    end

    it 'deletes the post when its origin shows a tombstone in its place' do
      origin_answers(200, { 'id' => status.ap_id, 'type' => 'Tombstone' })

      described_class.perform_now('Delete', status.ap_id, author.ap_id)

      expect(ActivityPubObject.exists?(status.id)).to be(false)
    end

    it 'keeps the post while its origin still has it' do
      origin_answers(200, note('<p>before</p>'))

      described_class.perform_now('Delete', status.ap_id, author.ap_id)

      expect(ActivityPubObject.exists?(status.id)).to be(true)
    end

    it 'keeps the post when its origin cannot answer' do
      origin_answers(503)

      described_class.perform_now('Delete', status.ap_id, author.ap_id)

      expect(ActivityPubObject.exists?(status.id)).to be(true)
    end

    it 'does not check a post only some people can see, which may look missing just for lack of permission' do
      status.update!(visibility: 'private')
      origin_answers(404)

      described_class.perform_now('Delete', status.ap_id, author.ap_id)

      expect(ActivityPubObject.exists?(status.id)).to be(true)
      expect(HTTParty).not_to have_received(:get)
    end

    it 'does nothing when the activity names someone other than the author' do
      origin_answers(404)

      described_class.perform_now('Delete', status.ap_id, 'https://origin.example/users/bob')

      expect(ActivityPubObject.exists?(status.id)).to be(true)
      expect(HTTParty).not_to have_received(:get)
    end
  end

  describe 'a forwarded Update' do
    it 'applies the latest content fetched from the origin' do
      origin_answers(200, note('<p>after</p>'))

      described_class.perform_now('Update', status.ap_id, author.ap_id)

      expect(status.reload.content).to eq('<p>after</p>')
      expect(status.edited_at).to be_present
    end

    it 'ignores the copy when the origin names another author' do
      origin_answers(200, note('<p>after</p>', author_uri: 'https://origin.example/users/bob'))

      described_class.perform_now('Update', status.ap_id, author.ap_id)

      expect(status.reload.content).to eq('<p>before</p>')
    end

    it 'leaves the post as it is when the origin cannot answer' do
      origin_answers(503)

      described_class.perform_now('Update', status.ap_id, author.ap_id)

      expect(status.reload.content).to eq('<p>before</p>')
    end
  end
end
