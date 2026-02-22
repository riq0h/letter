# frozen_string_literal: true

require 'rails_helper'

# StatusSerializationHelperのエンティティフィールドテスト
RSpec.describe 'Status entity fields' do
  # テスト用にconcernをincludeしたダミーコントローラを作成
  let(:controller_class) do
    Class.new(Api::BaseController) do
      include StatusSerializationHelper
    end
  end

  let(:user) { create(:actor, local: true) }
  let(:controller_instance) do
    ctrl = controller_class.new
    allow(ctrl).to receive_messages(current_user: user, params: {})
    ctrl
  end

  describe 'serialized_status' do
    let(:status) { create(:activity_pub_object, :note, actor: user) }

    it 'includes muted field' do
      result = controller_instance.send(:serialized_status, status)
      expect(result).to have_key(:muted)
      expect(result[:muted]).to be(false)
    end

    it 'sets muted to true when actor is muted' do
      muted_actor = create(:actor, local: true)
      muted_status = create(:activity_pub_object, :note, actor: muted_actor)
      create(:mute, actor: user, target_actor: muted_actor)

      result = controller_instance.send(:serialized_status, muted_status)
      expect(result[:muted]).to be(true)
    end

    it 'includes filtered field as empty array' do
      result = controller_instance.send(:serialized_status, status)
      expect(result).to have_key(:filtered)
      expect(result[:filtered]).to eq([])
    end

    it 'includes application field for local statuses' do
      result = controller_instance.send(:serialized_status, status)
      expect(result).to have_key(:application)
      expect(result[:application]).to eq({ name: 'letter', website: nil })
    end

    it 'sets application to nil for remote statuses' do
      remote_actor = create(:actor, :remote)
      remote_status = create(:activity_pub_object, :note, :remote, actor: remote_actor)

      result = controller_instance.send(:serialized_status, remote_status)
      expect(result[:application]).to be_nil
    end
  end
end
