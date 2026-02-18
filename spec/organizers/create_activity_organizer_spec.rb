# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreateActivityOrganizer do
  let(:sender) { create(:actor, :remote) }
  let(:activity) do
    {
      'type' => 'Create',
      'object' => {
        'id' => 'https://example.com/posts/123',
        'type' => 'Note',
        'content' => 'Hello world!',
        'published' => '2023-01-01T00:00:00Z'
      }
    }
  end

  describe '.call' do
    it 'returns success for valid create activity' do
      result = described_class.call(activity, sender)

      expect(result).to be_success
      expect(result.object).to be_a(ActivityPubObject)
      expect(result.object.content).to eq('<p>Hello world!</p>')
    end

    it 'returns failure for invalid object' do
      invalid_activity = { 'type' => 'Create', 'object' => 'invalid' }

      result = described_class.call(invalid_activity, sender)

      expect(result).to be_failure
      expect(result.error).to eq('Invalid object in Create activity')
    end

    it 'handles existing objects gracefully' do
      create(:activity_pub_object, ap_id: 'https://example.com/posts/123')

      result = described_class.call(activity, sender)

      expect(result).to be_success
      expect(result.object).to be_nil
    end

    it 'handles Vote-type objects separately' do
      vote_activity = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://example.com/votes/1',
          'type' => 'Vote',
          'inReplyTo' => 'https://example.com/polls/1',
          'name' => 'Option 1'
        }
      }

      result = described_class.call(vote_activity, sender)

      expect(result).to be_success
      expect(result.object).to be_nil
    end

    it 'detects Mastodon-style vote (Note with name pointing to poll)' do
      local_actor = create(:actor, local: true)
      status = create(:activity_pub_object, actor: local_actor, object_type: 'Question',
                                            ap_id: 'https://letter.test/posts/poll1')
      poll = create(:poll, object: status)

      vote_activity = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://remote.example.com/notes/vote1',
          'type' => 'Note',
          'name' => 'Option 1',
          'inReplyTo' => 'https://letter.test/posts/poll1',
          'attributedTo' => sender.ap_id
        }
      }

      expect do
        described_class.call(vote_activity, sender)
      end.to change(PollVote, :count).by(1)

      vote = PollVote.last
      expect(vote.poll).to eq(poll)
      expect(vote.actor).to eq(sender)
      expect(vote.choice).to eq(0)
    end

    it 'does not create ActivityPubObject for vote-like Notes' do
      local_actor = create(:actor, local: true)
      status = create(:activity_pub_object, actor: local_actor, object_type: 'Question',
                                            ap_id: 'https://letter.test/posts/poll2')
      create(:poll, object: status)

      vote_activity = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://remote.example.com/notes/vote2',
          'type' => 'Note',
          'name' => 'Option 2',
          'inReplyTo' => 'https://letter.test/posts/poll2',
          'attributedTo' => sender.ap_id
        }
      }

      expect do
        described_class.call(vote_activity, sender)
      end.not_to change(ActivityPubObject, :count)
    end
  end

  describe '#call' do
    subject(:organizer) { described_class.new(activity, sender) }

    it 'creates object with correct attributes' do
      result = organizer.call

      expect(result).to be_success
      object = result.object
      expect(object.ap_id).to eq('https://example.com/posts/123')
      expect(object.actor).to eq(sender)
      expect(object.object_type).to eq('Note')
      expect(object.content).to eq('<p>Hello world!</p>')
      expect(object.local).to be(false)
    end

    it 'processes mentions correctly' do
      local_actor = create(:actor, local: true)
      mentioned_ap_id = local_actor.ap_id
      activity_with_mention = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://example.com/posts/124',
          'type' => 'Note',
          'content' => 'Hello @mentioned!',
          'tag' => [
            {
              'type' => 'Mention',
              'href' => mentioned_ap_id
            }
          ]
        }
      }

      organizer = described_class.new(activity_with_mention, sender)
      result = organizer.call

      expect(result).to be_success
      expect(Mention.count).to eq(1)
      mention = Mention.first
      expect(mention.actor).to eq(local_actor)
      expect(mention.object).to eq(result.object)
    end

    it 'processes polls correctly' do
      poll_activity = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://example.com/polls/1',
          'type' => 'Question',
          'content' => 'What is your favorite color?',
          'oneOf' => [
            { 'name' => 'Red' },
            { 'name' => 'Blue' }
          ],
          'endTime' => 1.day.from_now.iso8601
        }
      }

      organizer = described_class.new(poll_activity, sender)
      result = organizer.call

      expect(result).to be_success
      expect(Poll.count).to eq(1)
      poll = Poll.first
      expect(poll.object).to eq(result.object)
      expect(poll.options.count).to eq(2)
      expect(poll.multiple).to be(false)
    end

    it 'extracts remote vote counts from replies.totalItems' do
      poll_activity = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://example.com/polls/vote-counts',
          'type' => 'Question',
          'content' => 'Pick one',
          'oneOf' => [
            { 'name' => 'A', 'replies' => { 'totalItems' => 42 } },
            { 'name' => 'B', 'replies' => { 'totalItems' => 18 } }
          ],
          'endTime' => 1.day.from_now.iso8601,
          'votersCount' => 60
        }
      }

      organizer = described_class.new(poll_activity, sender)
      result = organizer.call

      expect(result).to be_success
      poll = Poll.last
      expect(poll.votes_count).to eq(60)
      expect(poll.voters_count).to eq(60)
      expect(poll.options[0]['votes_count']).to eq(42)
      expect(poll.options[1]['votes_count']).to eq(18)
    end

    it 'creates poll with closed field as expiry' do
      poll_activity = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://example.com/polls/closed',
          'type' => 'Question',
          'content' => 'Closed poll',
          'closed' => 2.hours.from_now.iso8601,
          'oneOf' => [
            { 'name' => 'X' },
            { 'name' => 'Y' }
          ]
        }
      }

      organizer = described_class.new(poll_activity, sender)
      result = organizer.call

      expect(result).to be_success
      poll = Poll.last
      expect(poll.expires_at).to be_within(2.seconds).of(2.hours.from_now)
    end

    it 'creates already-expired remote poll' do
      poll_activity = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://example.com/polls/expired',
          'type' => 'Question',
          'content' => 'Old poll',
          'closed' => 1.hour.ago.iso8601,
          'oneOf' => [
            { 'name' => 'P', 'replies' => { 'totalItems' => 7 } },
            { 'name' => 'Q', 'replies' => { 'totalItems' => 3 } }
          ],
          'votersCount' => 10
        }
      }

      organizer = described_class.new(poll_activity, sender)
      result = organizer.call

      expect(result).to be_success
      poll = Poll.last
      expect(poll.expired?).to be true
      expect(poll.votes_count).to eq(10)
    end

    it 'schedules expiration job for polls' do
      expires_at = 1.day.from_now
      poll_activity = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://example.com/polls/2',
          'type' => 'Question',
          'content' => 'What is your favorite color?',
          'oneOf' => [
            { 'name' => 'Red' },
            { 'name' => 'Blue' }
          ],
          'endTime' => expires_at.iso8601
        }
      }

      allow(PollExpirationNotifyJob).to receive(:set).with(wait_until: be_within(1.second).of(expires_at)).and_return(PollExpirationNotifyJob)
      expect(PollExpirationNotifyJob).to receive(:perform_later)

      organizer = described_class.new(poll_activity, sender)
      result = organizer.call

      expect(result).to be_success
    end

    it 'processes custom emojis correctly' do
      emoji_activity = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://example.com/posts/125',
          'type' => 'Note',
          'content' => 'Hello :custom_emoji:!',
          'tag' => [
            {
              'type' => 'Emoji',
              'name' => ':custom_emoji:',
              'icon' => {
                'url' => 'https://example.com/emoji.png'
              }
            }
          ]
        }
      }

      organizer = described_class.new(emoji_activity, sender)
      result = organizer.call

      expect(result).to be_success
      expect(CustomEmoji.count).to eq(1)
      emoji = CustomEmoji.first
      expect(emoji.shortcode).to eq('custom_emoji')
      expect(emoji.domain).to eq('example.com')
      expect(emoji.image_url).to eq('https://example.com/emoji.png')
    end

    it 'updates reply count when replying to existing object' do
      parent_object = create(:activity_pub_object, ap_id: 'https://example.com/posts/parent')
      reply_activity = {
        'type' => 'Create',
        'object' => {
          'id' => 'https://example.com/posts/reply',
          'type' => 'Note',
          'content' => 'This is a reply',
          'inReplyTo' => 'https://example.com/posts/parent'
        }
      }

      organizer = described_class.new(reply_activity, sender)
      result = organizer.call

      expect(result).to be_success
      parent_object.reload
      expect(parent_object.replies_count).to eq(1)
    end

    context 'with relay information' do
      let(:relay) { Relay.create!(inbox_url: 'https://relay.example.com/inbox', state: 'accepted') }

      it 'preserves relay information in object' do
        organizer = described_class.new(activity, sender, preserve_relay_info: relay)
        result = organizer.call

        expect(result).to be_success
        expect(result.object.relay_id).to eq(relay.id)
      end
    end
  end

  describe 'Result class' do
    describe '#success?' do
      it 'returns true for successful result' do
        result = described_class::Result.new(success: true)
        expect(result).to be_success
      end

      it 'returns false for failed result' do
        result = described_class::Result.new(success: false)
        expect(result).not_to be_success
      end
    end

    describe '#failure?' do
      it 'returns false for successful result' do
        result = described_class::Result.new(success: true)
        expect(result).not_to be_failure
      end

      it 'returns true for failed result' do
        result = described_class::Result.new(success: false)
        expect(result).to be_failure
      end
    end

    describe 'immutability' do
      it 'is immutable' do
        result = described_class::Result.new(success: true)
        expect(result).to be_frozen
      end
    end
  end
end
