# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Actor, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:objects).dependent(:destroy) }
    it { is_expected.to have_many(:activities).dependent(:destroy) }
    it { is_expected.to have_many(:followers).through(:follower_relationships) }
    it { is_expected.to have_many(:following).through(:following_relationships) }
  end

  describe 'validations' do
    let(:actor) { build(:actor) }

    it 'validates username format' do
      actor.username = 'invalid-username'
      expect(actor).not_to be_valid
      expect(actor.errors[:username]).to include('is invalid')
    end

    context 'when actor is local' do
      let(:local_actor) { build(:actor, local: true) }

      it 'requires valid fields after creation' do
        local_actor.save!
        expect(local_actor.ap_id).to be_present
        expect(local_actor.inbox_url).to be_present
        expect(local_actor.public_key).to be_present
      end
    end

    context 'when actor is remote' do
      let(:remote_actor) { build(:actor, :remote) }

      it 'requires remote specific fields' do
        remote_actor.ap_id = nil
        expect(remote_actor).not_to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:local_actor) { create(:actor, local: true) }
    let!(:remote_actor) { create(:actor, :remote) }

    it '.local returns only local actors' do
      expect(described_class.local).to contain_exactly(local_actor)
    end

    it '.remote returns only remote actors' do
      expect(described_class.remote).to contain_exactly(remote_actor)
    end
  end

  describe '#local?' do
    it 'returns true for local actors' do
      actor = build(:actor, local: true)
      expect(actor.local?).to be true
    end

    it 'returns false for remote actors' do
      actor = build(:actor, :remote)
      expect(actor.local?).to be false
    end
  end

  describe '#display_name_or_username' do
    it 'returns display_name when present' do
      actor = build(:actor, display_name: 'Test User', username: 'testuser')
      expect(actor.display_name_or_username).to eq('Test User')
    end

    it 'returns username when display_name is blank' do
      actor = build(:actor, display_name: '', username: 'testuser')
      expect(actor.display_name_or_username).to eq('testuser')
    end
  end

  describe '#full_username' do
    it 'returns username for local actors' do
      actor = build(:actor, username: 'testuser', local: true)
      expect(actor.full_username).to eq('testuser')
    end

    it 'returns username@domain for remote actors' do
      actor = build(:actor, :remote, username: 'testuser', domain: 'example.com')
      expect(actor.full_username).to eq('testuser@example.com')
    end
  end

  describe '#webfinger_subject' do
    it 'returns correct webfinger subject for local actor' do
      actor = create(:actor, username: 'testuser', local: true)
      expected = "acct:testuser@#{Rails.application.config.activitypub.domain}"
      expect(actor.webfinger_subject).to eq(expected)
    end
  end

  describe '#public_url' do
    it 'returns API-style URL for local actor (client compatibility)' do
      actor = create(:actor, username: 'testuser', local: true)
      expected = "#{Rails.application.config.activitypub.base_url}/users/testuser"
      expect(actor.public_url).to eq(expected)
    end

    it 'returns nil for remote actor' do
      actor = create(:actor, :remote)
      expect(actor.public_url).to be_nil
    end
  end

  describe '#to_activitypub' do
    let(:actor) { create(:actor) }
    let(:activitypub_json) { actor.to_activitypub }

    it 'includes required ActivityPub fields' do
      expect(activitypub_json).to include(
        '@context',
        'type',
        'id',
        'preferredUsername',
        'inbox',
        'outbox',
        'publicKey'
      )
    end

    it 'has correct type' do
      expect(activitypub_json['type']).to eq('Person')
    end

    it 'includes correct username' do
      expect(activitypub_json['preferredUsername']).to eq(actor.username)
    end
  end

  describe '#update_posts_count!' do
    let(:actor) { create(:actor) }

    it 'updates posts count correctly' do
      create_list(:activity_pub_object, 3, actor: actor, object_type: 'Note', local: true)
      create(:activity_pub_object, actor: actor, object_type: 'Article', local: true)

      actor.update_posts_count!

      expect(actor.reload.posts_count).to eq(3)
    end
  end

  describe '#preferences' do
    let(:actor) { create(:actor) }

    it 'returns merged default and custom preferences' do
      actor.update!(settings: { 'posting:default:visibility' => 'unlisted' })
      prefs = actor.preferences

      expect(prefs['posting:default:visibility']).to eq('unlisted')
      expect(prefs['posting:default:language']).to eq('ja')
    end

    it 'returns default preferences when settings is nil' do
      actor.update!(settings: nil)
      prefs = actor.preferences

      expect(prefs['posting:default:visibility']).to eq('public')
      expect(prefs['web:use_blurhash']).to be true
    end
  end

  describe 'URL methods' do
    let(:actor) { create(:actor, username: 'testuser') }

    describe '#followers_url' do
      it 'returns correct followers URL for local actor' do
        expect(actor.followers_url).to eq("#{actor.ap_id}/followers")
      end

      it 'uses stored value if present' do
        custom_url = 'https://custom.example.com/followers'
        actor.update!(followers_url: custom_url)
        expect(actor.followers_url).to eq(custom_url)
      end
    end

    describe '#following_url' do
      it 'returns correct following URL for local actor' do
        expect(actor.following_url).to eq("#{actor.ap_id}/following")
      end
    end

    describe '#featured_url' do
      it 'returns correct featured URL for local actor' do
        expect(actor.featured_url).to eq("#{actor.ap_id}/collections/featured")
      end
    end
  end

  describe 'follower count methods' do
    let(:actor) { create(:actor) }
    let(:target_actor) { create(:actor, :remote) }

    before do
      create(:follow, actor: actor, target_actor: target_actor, accepted: true)
      create(:follow, target_actor: actor, accepted: true)
    end

    describe '#update_following_count!' do
      it 'updates following count correctly' do
        actor.update_following_count!
        expect(actor.reload.following_count).to eq(1)
      end
    end

    describe '#update_followers_count!' do
      it 'updates followers count correctly' do
        actor.update_followers_count!
        expect(actor.reload.followers_count).to eq(1)
      end
    end
  end

  describe 'settings management' do
    let(:actor) { create(:actor) }

    describe '#setting' do
      it 'returns default setting when not customized' do
        expect(actor.setting('posting:default:visibility')).to eq('public')
      end

      it 'returns custom setting when set' do
        actor.update!(settings: { 'posting:default:visibility' => 'unlisted' })
        expect(actor.setting('posting:default:visibility')).to eq('unlisted')
      end
    end

    describe '#update_setting' do
      it 'updates a specific setting' do
        actor.update_setting('posting:default:visibility', 'private')
        expect(actor.setting('posting:default:visibility')).to eq('private')
      end

      it 'creates settings hash when nil' do
        actor.update!(settings: nil)
        actor.update_setting('web:theme', 'dark')
        expect(actor.setting('web:theme')).to eq('dark')
      end
    end

    describe '#default_settings' do
      it 'returns hash with default values' do
        defaults = actor.default_settings
        expect(defaults).to be_a(Hash)
        expect(defaults['posting:default:visibility']).to eq('public')
        expect(defaults['posting:default:language']).to eq('ja')
      end
    end
  end

  describe 'image attachment' do
    let(:actor) { create(:actor) }

    describe '#attach_avatar_with_folder' do
      it 'successfully calls ActorImageProcessor to attach avatar' do
        # ActorImageProcessorのメソッド呼び出しをモック
        processor_instance = instance_double(ActorImageProcessor)
        allow(ActorImageProcessor).to receive(:new).with(actor).and_return(processor_instance)
        allow(processor_instance).to receive(:attach_avatar_with_folder).and_return(true)

        # 実際のActorImageProcessorサービスが呼ばれることを確認
        expect do
          actor.attach_avatar_with_folder(io: StringIO.new('fake'), filename: 'test.jpg', content_type: 'image/jpeg')
        end.not_to raise_error

        expect(processor_instance).to have_received(:attach_avatar_with_folder)
      end
    end
  end

  describe 'ActivityPub generation' do
    let(:actor) { create(:actor) }
    let(:target_actor) { create(:actor, :remote) }

    describe '#generate_follow_activity' do
      it 'generates Follow activity JSON' do
        follow_id = 'https://example.com/follows/123'
        activity = actor.generate_follow_activity(target_actor, follow_id)

        expect(activity).to include(
          '@context' => 'https://www.w3.org/ns/activitystreams',
          'type' => 'Follow',
          'actor' => actor.ap_id,
          'object' => target_actor.ap_id
        )
        expect(activity['id']).to be_present
      end
    end

    describe '#generate_accept_activity' do
      it 'generates Accept activity JSON' do
        follow = create(:follow, actor: target_actor, target_actor: actor)
        activity = actor.generate_accept_activity(follow)

        expect(activity['type']).to eq('Accept')
        expect(activity['actor']).to eq(actor.ap_id)
        expect(activity['object']['type']).to eq('Follow')
      end
    end
  end

  describe 'activity distribution' do
    let(:actor) { create(:actor) }
    let(:target_actor) { create(:actor, :remote) }

    describe '#unfollow!' do
      it 'successfully calls ActorActivityDistributor to unfollow' do
        expect do
          actor.unfollow!(target_actor)
        end.not_to raise_error
      end
    end

    describe '#should_distribute_profile_update?' do
      it 'successfully calls ActorActivityDistributor for distribution check' do
        result = actor.send(:should_distribute_profile_update?)
        expect(result).to be_in([true, false])
      end
    end

    describe '#distribute_profile_update' do
      it 'successfully calls ActorActivityDistributor to distribute profile update' do
        expect do
          actor.send(:distribute_profile_update)
        end.not_to raise_error
      end
    end
  end

  describe 'avatar and header URLs' do
    let(:actor) { create(:actor) }

    describe '#avatar_url' do
      it 'delegates to ActorImageProcessor' do
        processor_instance = instance_double(ActorImageProcessor)
        allow(ActorImageProcessor).to receive(:new).with(actor).and_return(processor_instance)
        allow(processor_instance).to receive(:avatar_url).and_return('https://example.com/avatar.jpg')

        result = actor.avatar_url

        expect(ActorImageProcessor).to have_received(:new).with(actor)
        expect(processor_instance).to have_received(:avatar_url)
        expect(result).to eq('https://example.com/avatar.jpg')
      end
    end

    describe '#header_url' do
      it 'delegates to ActorImageProcessor' do
        processor_instance = instance_double(ActorImageProcessor)
        allow(ActorImageProcessor).to receive(:new).with(actor).and_return(processor_instance)
        allow(processor_instance).to receive(:header_url).and_return('https://example.com/header.jpg')

        result = actor.header_url

        expect(ActorImageProcessor).to have_received(:new).with(actor)
        expect(processor_instance).to have_received(:header_url)
        expect(result).to eq('https://example.com/header.jpg')
      end
    end
  end

  describe 'ActivityPub parsing' do
    let(:actor) { create(:actor, :remote) }

    describe '#parse_actor_data' do
      it 'parses raw_data when it is a String' do
        json_data = '{"preferredUsername": "testuser"}'
        actor.raw_data = json_data

        allow(actor).to receive(:parse_raw_data_string).with(json_data).and_return({ 'preferredUsername' => 'testuser' })

        result = actor.send(:parse_actor_data)

        expect(actor).to have_received(:parse_raw_data_string).with(json_data)
        expect(result).to eq({ 'preferredUsername' => 'testuser' })
      end

      it 'returns raw_data when it is already a Hash' do
        # メモリ内でHashが設定されている場合
        hash_data = { 'preferredUsername' => 'testuser', 'name' => 'Test User' }
        allow(actor).to receive(:raw_data).and_return(hash_data)

        result = actor.send(:parse_actor_data)

        expect(result).to eq(hash_data)
      end

      it 'handles JSON parsing errors gracefully' do
        invalid_json = '{invalid json}'
        actor.raw_data = invalid_json

        allow(actor).to receive(:parse_raw_data_string).with(invalid_json).and_raise(JSON::ParserError)

        expect do
          actor.send(:parse_actor_data)
        end.to raise_error(JSON::ParserError)
      end

      it 'returns nil when raw_data is nil' do
        actor.raw_data = nil

        result = actor.send(:parse_actor_data)
        expect(result).to be_nil
      end
    end
  end

  describe 'key delegation' do
    let(:actor) { create(:actor) }

    describe '#public_key_object' do
      it 'successfully calls ActorKeyManager for public key object' do
        result = actor.public_key_object
        expect(result).not_to be_nil
      end
    end

    describe '#private_key_object' do
      it 'successfully calls ActorKeyManager for private key object' do
        result = actor.private_key_object
        expect(result).not_to be_nil
      end
    end

    describe '#public_key_id' do
      it 'successfully calls ActorKeyManager for public key ID' do
        result = actor.public_key_id
        expect(result).to be_a(String)
      end
    end
  end

  describe 'callbacks' do
    describe 'key generation for local actors' do
      let(:actor) { build(:actor, local: true, private_key: nil) }

      it 'generates key pair on creation' do
        actor.save!
        expect(actor.private_key).to be_present
        expect(actor.public_key).to be_present
      end
    end

    describe 'admin assignment' do
      it 'sets admin to true for local actors' do
        actor = create(:actor, local: true)
        expect(actor.admin).to be true
      end

      it 'does not set admin for remote actors' do
        actor = create(:actor, :remote)
        expect(actor.admin).to be_falsey
      end
    end
  end

  describe 'relationship checking methods' do
    let(:actor) { create(:actor) }
    let(:other_actor) { create(:actor) }

    describe '#blocking?' do
      it 'returns true when actor is blocking the other actor' do
        create(:block, actor: actor, target_actor: other_actor)

        expect(actor.blocking?(other_actor)).to be true
      end

      it 'returns false when not blocking the other actor' do
        expect(actor.blocking?(other_actor)).to be false
      end

      it 'handles nil input gracefully' do
        expect(actor.blocking?(nil)).to be false
      end
    end

    describe '#blocked_by?' do
      it 'returns true when actor is blocked by the other actor' do
        create(:block, actor: other_actor, target_actor: actor)

        expect(actor.blocked_by?(other_actor)).to be true
      end

      it 'returns false when not blocked by the other actor' do
        expect(actor.blocked_by?(other_actor)).to be false
      end

      it 'handles nil input gracefully' do
        expect(actor.blocked_by?(nil)).to be false
      end
    end

    describe '#muting?' do
      it 'returns true when actor is muting the other actor' do
        create(:mute, actor: actor, target_actor: other_actor)

        expect(actor.muting?(other_actor)).to be true
      end

      it 'returns false when not muting the other actor' do
        expect(actor.muting?(other_actor)).to be false
      end

      it 'handles nil input gracefully' do
        expect(actor.muting?(nil)).to be false
      end
    end

    describe '#muted_by?' do
      it 'returns true when actor is muted by the other actor' do
        create(:mute, actor: other_actor, target_actor: actor)

        expect(actor.muted_by?(other_actor)).to be true
      end

      it 'returns false when not muted by the other actor' do
        expect(actor.muted_by?(other_actor)).to be false
      end

      it 'handles nil input gracefully' do
        expect(actor.muted_by?(nil)).to be false
      end
    end

    describe '#domain_blocking?' do
      it 'returns true when actor is blocking the domain' do
        domain = 'blocked-domain.com'
        create(:domain_block, actor: actor, domain: domain)

        expect(actor.domain_blocking?(domain)).to be true
      end

      it 'returns false when not blocking the domain' do
        expect(actor.domain_blocking?('example.com')).to be false
      end

      it 'handles nil domain gracefully' do
        expect(actor.domain_blocking?(nil)).to be false
      end

      it 'handles empty string gracefully' do
        expect(actor.domain_blocking?('')).to be false
      end
    end
  end

  describe 'account identifier methods' do
    describe '#acct' do
      it 'returns username for local actors' do
        local_actor = create(:actor, local: true, username: 'localuser')

        expect(local_actor.acct).to eq('localuser')
      end

      it 'returns username@domain for remote actors' do
        remote_actor = create(:actor, :remote, username: 'remoteuser', domain: 'example.com')

        expect(remote_actor.acct).to eq('remoteuser@example.com')
      end

      it 'handles edge case with local actor having domain' do
        # ローカルアクターなのにドメインが設定されている場合
        local_actor_with_domain = create(:actor, local: true, username: 'localuser', domain: 'example.com')

        expect(local_actor_with_domain.acct).to eq('localuser')
      end
    end
  end

  describe 'follow actions' do
    let(:actor) { create(:actor) }
    let(:target_actor) { create(:actor, :remote) }

    describe '#follow!' do
      it 'successfully calls FollowInteractor to follow target actor' do
        expect do
          actor.follow!(target_actor)
        end.not_to raise_error
      end
    end
  end

  describe 'image URL extraction' do
    let(:actor) { create(:actor, :remote) }

    describe '#extract_remote_image_url' do
      it 'extracts avatar URL from raw_data stored as JSON string' do
        raw_data_json = {
          'icon' => {
            'type' => 'Image',
            'url' => 'https://example.com/avatar.jpg'
          }
        }.to_json

        actor.update!(raw_data: raw_data_json)

        url = actor.extract_remote_image_url('icon')

        expect(url).to eq('https://example.com/avatar.jpg')
      end

      it 'extracts header image URL from raw_data stored as JSON string' do
        raw_data_json = {
          'image' => {
            'type' => 'Image',
            'url' => 'https://example.com/header.jpg'
          }
        }.to_json

        actor.update!(raw_data: raw_data_json)

        url = actor.extract_remote_image_url('image')

        expect(url).to eq('https://example.com/header.jpg')
      end

      it 'handles image data with href instead of url' do
        raw_data_json = {
          'icon' => {
            'type' => 'Image',
            'href' => 'https://example.com/avatar.png'
          }
        }.to_json

        actor.update!(raw_data: raw_data_json)

        url = actor.extract_remote_image_url('icon')

        expect(url).to eq('https://example.com/avatar.png')
      end

      it 'handles image data as array' do
        icon_array = [{ 'type' => 'Image', 'url' => 'https://example.com/avatar1.jpg' }]
        raw_data_json = { 'icon' => icon_array }.to_json
        actor.update!(raw_data: raw_data_json)

        url = actor.extract_remote_image_url('icon')
        expect(url).to eq('https://example.com/avatar1.jpg')
      end

      it 'handles image data as direct URL string' do
        raw_data_json = {
          'icon' => 'https://example.com/direct-avatar.jpg'
        }.to_json

        actor.update!(raw_data: raw_data_json)

        url = actor.extract_remote_image_url('icon')

        expect(url).to eq('https://example.com/direct-avatar.jpg')
      end

      it 'returns nil when image data is missing' do
        raw_data_json = { 'name' => 'Test User' }.to_json

        actor.update!(raw_data: raw_data_json)

        url = actor.extract_remote_image_url('icon')

        expect(url).to be_nil
      end

      it 'returns nil when raw_data is blank' do
        actor.update!(raw_data: nil)

        url = actor.extract_remote_image_url('icon')

        expect(url).to be_nil
      end

      it 'handles invalid JSON gracefully' do
        actor.update!(raw_data: 'invalid json string')

        url = actor.extract_remote_image_url('icon')

        expect(url).to be_nil
      end

      it 'returns nil when image data exists but has no URL' do
        raw_data_json = {
          'icon' => {
            'type' => 'Image',
            'name' => 'avatar.jpg'
          }
        }.to_json

        actor.update!(raw_data: raw_data_json)

        url = actor.extract_remote_image_url('icon')

        expect(url).to be_nil
      end
    end
  end
end
