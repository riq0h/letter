# frozen_string_literal: true

require 'rails_helper'

# AccountSerializerのエンティティフィールドテスト
RSpec.describe 'Account entity fields' do
  let(:controller_class) do
    Class.new(Api::BaseController) do
      include AccountSerializer
    end
  end

  let(:user) { create(:actor, local: true) }
  let(:controller_instance) do
    ctrl = controller_class.new
    allow(ctrl).to receive_messages(current_user: user, params: {})
    ctrl
  end

  describe 'serialized_account' do
    it 'includes last_status_at from actual posts' do
      create(:activity_pub_object, :note, actor: user, published_at: 1.day.ago)

      result = controller_instance.send(:serialized_account, user)
      expect(result[:last_status_at]).to be_present
      expect(result[:last_status_at]).to be_a(String)
    end

    it 'returns nil for last_status_at when no posts' do
      result = controller_instance.send(:serialized_account, user)
      expect(result[:last_status_at]).to be_nil
    end

    it 'includes suspended field' do
      result = controller_instance.send(:serialized_account, user)
      expect(result).to have_key(:suspended)
      expect(result[:suspended]).to be(false)
    end

    it 'includes moved field as nil' do
      result = controller_instance.send(:serialized_account, user)
      expect(result).to have_key(:moved)
      expect(result[:moved]).to be_nil
    end

    it 'includes roles field' do
      result = controller_instance.send(:serialized_account, user)
      expect(result).to have_key(:roles)
      expect(result[:roles]).to eq([])
    end

    it 'includes admin role for self when admin' do
      admin = create(:actor, :admin, local: true)
      allow(controller_instance).to receive(:current_user).and_return(admin)

      result = controller_instance.send(:serialized_account, admin, is_self: true)
      expect(result[:roles]).to include(hash_including(name: 'Admin'))
    end

    it 'includes source for self accounts' do
      result = controller_instance.send(:serialized_account, user, is_self: true)
      expect(result).to have_key(:source)
      expect(result[:source]).to have_key(:privacy)
      expect(result[:source]).to have_key(:sensitive)
      expect(result[:source]).to have_key(:language)
    end

    it 'includes verified_at from field data' do
      verified_time = '2024-01-01T00:00:00Z'
      user.update!(fields: [{ name: 'Website', value: 'https://example.com', verified_at: verified_time }].to_json)

      result = controller_instance.send(:serialized_account, user)
      field = result[:fields].first
      expect(field[:verified_at]).to eq(verified_time)
    end

    it 'returns nil verified_at when not verified' do
      user.update!(fields: [{ name: 'Website', value: 'https://example.com' }].to_json)

      result = controller_instance.send(:serialized_account, user)
      field = result[:fields].first
      expect(field[:verified_at]).to be_nil
    end
  end
end
