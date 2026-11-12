# frozen_string_literal: true

require 'rails_helper'

# 取得した投稿の作者が投稿idと別ホストなら、その作者の投稿として保存しない
RSpec.describe Search::RemoteResolverService do
  let(:service) { described_class.new }
  let!(:victim) { create(:actor, :remote, domain: 'victim.example', ap_id: 'https://victim.example/users/v') }

  def note(id:, author:)
    { 'id' => id, 'type' => 'Note', 'attributedTo' => author, 'content' => 'x',
      'published' => Time.current.iso8601, 'to' => ['https://www.w3.org/ns/activitystreams#Public'] }
  end

  it 'refuses a note whose author is on another host than its id' do
    result = service.send(:create_remote_object, note(id: 'https://attacker.example/notes/1', author: victim.ap_id))

    expect(result).to be_nil
    expect(ActivityPubObject.where(actor: victim)).to be_empty
  end

  it 'stores a note whose id and author share the host' do
    result = service.send(:create_remote_object, note(id: 'https://victim.example/notes/1', author: victim.ap_id))

    expect(result&.actor).to eq(victim)
  end

  it 'resolves through the verified fetch' do
    allow(service).to receive(:url_query?).and_return(true)
    allow(ActivityPubHttpClient).to receive(:fetch_verified).with('https://attacker.example/x').and_return(nil)

    expect(service.resolve_remote_status('https://attacker.example/x')).to be_nil
  end
end
