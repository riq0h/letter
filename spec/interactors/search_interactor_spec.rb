# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SearchInteractor do
  let(:current_user) { create(:actor) }
  let(:params) { { q: 'test query' } }

  describe '.search' do
    it 'returns failure for empty query' do
      result = described_class.search({ q: '' }, current_user)

      expect(result).to be_failure
      expect(result.error).to eq('Search query is required')
    end

    it 'returns success for valid query' do
      result = described_class.search(params, current_user)

      expect(result).to be_success
      expect(result.results).to have_key(:accounts)
      expect(result.results).to have_key(:statuses)
      expect(result.results).to have_key(:hashtags)
    end

    it 'searches local accounts' do
      local_actor = create(:actor, username: 'testuser', local: true)
      search_params = { q: 'testuser' }

      result = described_class.search(search_params, current_user)

      expect(result).to be_success
      expect(result.results[:accounts]).to include(local_actor)
    end

    it 'searches hashtags' do
      tag = create(:tag, name: 'testtag', usage_count: 10)
      search_params = { q: '#testtag' }

      result = described_class.search(search_params, current_user)

      expect(result).to be_success
      expect(result.results[:hashtags]).to include(tag)
    end

    context 'when remote resolution is enabled' do
      let(:remote_resolver) { instance_double(Search::RemoteResolverService) }
      let(:search_params) { { q: 'user@example.com', resolve: 'true' } }

      before do
        allow(Search::RemoteResolverService).to receive(:new).and_return(remote_resolver)
        allow(remote_resolver).to receive(:resolve_remote_account).and_return(nil)
      end

      it 'attempts to resolve remote account' do
        result = described_class.search(search_params, current_user)

        expect(result).to be_success
        expect(remote_resolver).to have_received(:resolve_remote_account).with('user@example.com')
      end
    end

    context 'when search type is specified' do
      it 'searches only accounts for accounts type' do
        search_params = { q: 'test', type: 'accounts' }

        result = described_class.search(search_params, current_user)

        expect(result).to be_success
        expect(result.results[:statuses]).to be_empty
        expect(result.results[:hashtags]).to be_empty
      end

      it 'searches only statuses for statuses type' do
        search_params = { q: 'test', type: 'statuses' }

        result = described_class.search(search_params, current_user)

        expect(result).to be_success
        expect(result.results[:accounts]).to be_empty
        expect(result.results[:hashtags]).to be_empty
      end

      it 'searches only hashtags for hashtags type' do
        search_params = { q: 'test', type: 'hashtags' }

        result = described_class.search(search_params, current_user)

        expect(result).to be_success
        expect(result.results[:accounts]).to be_empty
        expect(result.results[:statuses]).to be_empty
      end
    end
  end

  describe '#search' do
    subject(:interactor) { described_class.new(params, current_user) }

    it 'returns successful result' do
      result = interactor.search

      expect(result).to be_success
    end

    it 'returns proper search result structure' do
      result = interactor.search
      results = result.results

      expect(results).to have_key(:accounts)
      expect(results).to have_key(:statuses)
      expect(results).to have_key(:hashtags)
    end

    it 'returns arrays for each result type' do
      result = interactor.search
      results = result.results

      expect(results[:accounts]).to be_an(Array)
      expect(results[:statuses]).to be_an(Array)
      expect(results[:hashtags]).to be_an(Array)
    end

    context 'with @username format query' do
      let(:params) { { q: '@testuser' } }

      it 'processes as local username search' do
        local_actor = create(:actor, username: 'testuser', local: true)

        result = interactor.search

        expect(result).to be_success
        expect(result.results[:accounts]).to include(local_actor)
      end
    end

    context 'with URL format query' do
      let(:params) { { q: 'https://example.com/status/123', resolve: 'true' } }
      let(:remote_resolver) { instance_double(Search::RemoteResolverService) }

      before do
        allow(Search::RemoteResolverService).to receive(:new).and_return(remote_resolver)
        allow(remote_resolver).to receive(:resolve_remote_status).and_return(nil)
      end

      it 'attempts to resolve remote status' do
        result = interactor.search

        expect(result).to be_success
        expect(remote_resolver).to have_received(:resolve_remote_status)
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
