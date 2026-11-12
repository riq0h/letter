# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPubVisibilityHelper do
  let(:helper) { Class.new { include ActivityPubVisibilityHelper }.new }
  let(:public_collection) { 'https://www.w3.org/ns/activitystreams#Public' }
  let(:author) { 'https://origin.example/users/alice' }
  let(:mentioned) { 'https://other.example/users/bob' }
  let(:mention_tag) { [{ 'type' => 'Mention', 'href' => mentioned }] }

  def visibility(to:, cc: [], tag: nil)
    helper.send(:determine_visibility, { 'to' => to, 'cc' => cc, 'tag' => tag })
  end

  it 'classifies public and unlisted posts' do
    expect(visibility(to: [public_collection], cc: ["#{author}/followers"])).to eq('public')
    expect(visibility(to: ["#{author}/followers"], cc: [public_collection])).to eq('unlisted')
  end

  it 'classifies a followers-only reply that mentions someone as private, not direct' do
    result = visibility(to: ["#{author}/followers"], cc: [mentioned], tag: mention_tag)

    expect(result).to eq('private')
  end

  it 'classifies a followers-only post without mentions as private' do
    expect(visibility(to: ["#{author}/followers"])).to eq('private')
  end

  it 'classifies a message addressed only to mentioned actors as direct' do
    expect(visibility(to: [mentioned], tag: mention_tag)).to eq('direct')
  end
end
