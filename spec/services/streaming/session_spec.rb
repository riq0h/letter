# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Streaming::Session do
  let!(:user) { create(:actor) }
  let(:author) { create(:actor, :remote) }
  let(:sent) { [] }
  let(:transport) do
    messages = sent
    Object.new.tap { |t| t.define_singleton_method(:send_text) { |text| messages << JSON.parse(text) } }
  end
  let(:scopes) { %w[read write] }
  let(:session) { described_class.new(user: user, scopes: scopes, transport: transport) }

  def subscribe(stream, **params)
    session.receive({ type: 'subscribe', stream: stream, **params }.to_json)
  end

  def deliver(kind, target_id, recipient_id: nil, public_visibility: false)
    event = StreamingEvent.new(kind: kind, target_id: target_id.to_s, recipient_id: recipient_id,
                               public_visibility: public_visibility)
    session.deliver(event, Streaming::Renderer.new(user))
  end

  def add_to_home(item)
    if item.is_a?(Reblog)
      HomeFeedEntry.create!(sort_id: item.timeline_id, object_id: item.object_id.to_s, reblog_id: item.id,
                            actor_id: item.actor_id, created_at: Time.current)
    else
      HomeFeedEntry.create!(sort_id: item.id.to_s, object_id: item.id.to_s, actor_id: item.actor_id,
                            created_at: Time.current)
    end
  end

  def payload(message)
    JSON.parse(message['payload'])
  end

  describe 'subscriptions' do
    it 'subscribes and unsubscribes in the format Mastodon clients use' do
      subscribe('user')
      subscribe('hashtag', tag: 'Ruby')
      expect(session.subscriptions.map(&:name)).to eq([%w[user], %w[hashtag Ruby]])

      session.receive({ type: 'unsubscribe', stream: 'hashtag', tag: 'Ruby' }.to_json)
      expect(session.subscriptions.map(&:name)).to eq([%w[user]])
    end

    it 'subscribes to the stream given when connecting' do
      session.open('stream' => 'user:notification')

      expect(session.subscriptions.map(&:name)).to eq([%w[user:notification]])
    end

    it 'answers an error for an unknown stream' do
      subscribe('nonexistent')

      expect(sent).to eq([{ 'error' => 'Unknown stream type', 'status' => 400 }])
    end

    it 'refuses a stream the token is not allowed to read' do
      limited = described_class.new(user: user, scopes: %w[read:notifications], transport: transport)
      limited.receive({ type: 'subscribe', stream: 'user' }.to_json)
      limited.receive({ type: 'subscribe', stream: 'user:notification' }.to_json)

      expect(sent).to eq([{ 'error' => 'Access token does not have the required scopes', 'status' => 401 }])
      expect(limited.subscriptions.map(&:name)).to eq([%w[user:notification]])
    end

    it 'refuses a list of someone else' do
      subscribe('list', list: create(:list, actor: create(:actor)).id.to_s)

      expect(sent.first).to include('status' => 404)
      expect(session.subscriptions).to be_empty
    end

    it 'ignores a message that is not JSON' do
      session.receive('ping')

      expect(sent).to be_empty
    end
  end

  describe 'notifications' do
    let(:status) { create(:activity_pub_object, :remote, actor: author) }
    let(:notification) do
      create(:notification, account: user, from_account: author, notification_type: 'mention', activity_id: status.id.to_s)
    end

    before do
      subscribe('user')
      subscribe('user:notification')
    end

    it 'sends a notification to both the user stream and the notification stream' do
      deliver('notification', notification.id, recipient_id: user.id)

      expect(sent.map { |m| [m['stream'], m['event']] })
        .to eq([[%w[user], 'notification'], [%w[user:notification], 'notification']])
      expect(payload(sent.first)).to include('id' => notification.id.to_s, 'type' => 'mention')
      expect(payload(sent.first)['status']).to include('id' => status.id.to_s)
    end

    it 'does not send a notification meant for someone else' do
      deliver('notification', notification.id, recipient_id: author.id)

      expect(sent).to be_empty
    end
  end

  describe 'home timeline' do
    before { subscribe('user') }

    it 'sends a post added to the home timeline' do
      status = create(:activity_pub_object, :remote, actor: author)
      add_to_home(status)

      deliver('home', status.id, recipient_id: user.id)

      expect(sent.size).to eq(1)
      expect(sent.first).to include('stream' => %w[user], 'event' => 'update')
      expect(payload(sent.first)).to include('id' => status.id.to_s)
    end

    it 'sends a boost wrapping the boosted post' do
      status = create(:activity_pub_object, :remote, actor: create(:actor, :remote))
      reblog = create(:reblog, actor: author, object: status)
      add_to_home(reblog)

      deliver('home', reblog.timeline_id, recipient_id: user.id)

      expect(payload(sent.first)).to include('id' => reblog.timeline_id)
      expect(payload(sent.first)['reblog']).to include('id' => status.id.to_s)
    end

    it 'does not send a post by a muted account, as the home timeline does not show it' do
      status = create(:activity_pub_object, :remote, actor: author)
      add_to_home(status)
      create(:mute, actor: user, target_actor: author)

      deliver('home', status.id, recipient_id: user.id)

      expect(sent).to be_empty
    end
  end

  describe 'public timelines' do
    let(:remote_status) { create(:activity_pub_object, :remote, actor: author) }
    let(:local_status) { create(:activity_pub_object, actor: create(:actor)) }

    it 'sends a new public post to the matching public streams' do
      %w[public public:local public:remote public:media].each { |stream| subscribe(stream) }

      deliver('status', remote_status.id)

      expect(sent.pluck('stream')).to eq([%w[public], %w[public:remote]])
      expect(sent.pluck('event').uniq).to eq(['update'])
      expect(payload(sent.first)).to include('id' => remote_status.id.to_s)
    end

    it 'sends a post of this server to the local stream' do
      subscribe('public:local')

      deliver('status', local_status.id)

      expect(sent.pluck('stream')).to eq([%w[public:local]])
    end

    it 'sends a post with media to the media stream' do
      subscribe('public:media')
      create(:media_attachment, actor: author, object: remote_status)

      deliver('status', remote_status.id)

      expect(sent.pluck('stream')).to eq([%w[public:media]])
    end

    it 'does not send a followers-only post to the public streams' do
      subscribe('public')

      deliver('status', create(:activity_pub_object, :remote, :private, actor: author).id)

      expect(sent).to be_empty
    end
  end

  describe 'hashtag and list timelines' do
    let(:status) { create(:activity_pub_object, :remote, actor: author) }

    it 'sends a tagged post with the tag name the client subscribed with' do
      create(:object_tag, object: status, tag: create(:tag, name: 'ruby'))
      subscribe('hashtag', tag: 'Ruby')
      subscribe('hashtag:local', tag: 'Ruby')

      deliver('status', status.id)

      expect(sent.pluck('stream')).to eq([%w[hashtag Ruby]])
    end

    it 'sends a post by a member of the list' do
      list = create(:list, actor: user)
      create(:list_membership, list: list, actor: author)
      subscribe('list', list: list.id.to_s)

      deliver('status', status.id)
      deliver('status', create(:activity_pub_object, :remote, actor: create(:actor, :remote)).id)

      expect(sent.pluck('stream')).to eq([['list', list.id.to_s]])
    end
  end

  describe 'edits' do
    let(:status) { create(:activity_pub_object, :remote, actor: author) }

    it 'sends an edited post that is on the home timeline' do
      subscribe('user')
      add_to_home(status)

      deliver('status.update', status.id)

      expect(sent.first).to include('stream' => %w[user], 'event' => 'status.update')
      expect(payload(sent.first)).to include('id' => status.id.to_s)
    end

    it 'does not send an edited post that is not on the home timeline to the user stream' do
      subscribe('user')

      deliver('status.update', status.id)

      expect(sent).to be_empty
    end

    it 'sends an edited public post to the public stream' do
      subscribe('public')

      deliver('status.update', status.id)

      expect(sent.first).to include('stream' => %w[public], 'event' => 'status.update')
    end
  end

  describe 'deletes' do
    before do
      %w[user user:notification public].each { |stream| subscribe(stream) }
      subscribe('hashtag', tag: 'ruby')
    end

    it 'sends the id of a deleted public post to every stream it may have been on' do
      deliver('delete', '12345', public_visibility: true)

      expect(sent.pluck('stream')).to eq([%w[user], %w[public], %w[hashtag ruby]])
      expect(sent.first).to include('event' => 'delete', 'payload' => '12345')
    end

    it 'sends the id of another deleted post only to the user stream' do
      deliver('delete', '12345', public_visibility: false)

      expect(sent.pluck('stream')).to eq([%w[user]])
    end
  end

  describe 'direct messages' do
    it 'sends the updated conversation to the direct stream' do
      subscribe('direct')
      subscribe('user')
      message = create(:activity_pub_object, :remote, :direct, actor: author)
      conversation = Conversation.create!(unread: true, last_status: message)
      [user, author].each { |actor| conversation.conversation_participants.create!(actor: actor) }

      deliver('conversation', conversation.id, recipient_id: user.id)

      expect(sent.size).to eq(1)
      expect(sent.first).to include('stream' => %w[direct], 'event' => 'conversation')
      expect(payload(sent.first)).to include('id' => conversation.id.to_s)
      expect(payload(sent.first)['accounts'].pluck('id')).to eq([author.id.to_s])
    end
  end
end
