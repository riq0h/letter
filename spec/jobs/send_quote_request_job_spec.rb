# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendQuoteRequestJob do
  let(:me) { create(:actor) }
  let(:sender) { instance_double(ActivitySender) }
  let(:author) { create(:actor, :remote) }
  let(:quoted) { create(:activity_pub_object, :remote, actor: author) }
  let(:my_post) { create(:activity_pub_object, actor: me) }
  let(:authorization_uri) { "https://remote.example.com/users/#{author.username}/quote_authorizations/1" }

  def quote!
    QuotePost.create!(actor: me, object: my_post, quoted_object: quoted, ap_id: "#{my_post.ap_id}#quote")
  end

  before { allow(ActivitySender).to receive(:new).and_return(sender) }

  it 'sends a QuoteRequest naming the quoted post and the quoting post to the author' do
    quote_post = quote!
    allow(sender).to receive(:send_activity).and_return({ success: true, code: 202 })

    described_class.perform_now(quote_post.id)

    expect(sender).to have_received(:send_activity) do |activity:, target_inbox:, signing_actor:|
      expect(activity).to include('type' => 'QuoteRequest', 'id' => quote_post.quote_request_ap_id, 'actor' => me.ap_id,
                                  'object' => quoted.ap_id, 'instrument' => my_post.ap_id)
      expect(target_inbox).to eq(author.inbox_url)
      expect(signing_actor).to eq(me)
    end
  end

  it 'retries when the author server does not respond' do
    quote_post = quote!
    allow(sender).to receive(:send_activity).and_return({ success: false, error: 'Timeout: execution expired' })

    expect { described_class.perform_now(quote_post.id) }.to have_enqueued_job(described_class)
  end
end
