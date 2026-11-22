# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TagUsageHistory do
  include ActiveSupport::Testing::TimeHelpers

  let(:tag) { create(:tag) }

  def tag_post_by(actor, at: Time.current)
    travel_to(at) { create(:object_tag, tag: tag, object: create(:activity_pub_object, :remote, actor: actor)) }
  end

  it 'counts the uses and the accounts that used the tag today' do
    alice = create(:actor, :remote)
    bob = create(:actor, :remote)
    tag_post_by(alice)
    tag_post_by(alice)
    tag_post_by(bob)

    history = described_class.find_by!(tag: tag, date: Date.current)
    expect(history.uses).to eq(3)
    expect(history.accounts).to eq(2)
  end

  it 'does not count accounts that used the tag on earlier days' do
    earlier = create(:actor, :remote)
    tag_post_by(earlier, at: 2.days.ago)
    tag_post_by(create(:actor, :remote))

    expect(described_class.find_by!(tag: tag, date: Date.current).accounts).to eq(1)
  end
end
