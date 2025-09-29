# frozen_string_literal: true

require_relative '../concerns/actor_attachment_processing'
require_relative '../../controllers/concerns/activity_pub_visibility_helper'

module Search
  class RemoteResolverService
    include ActorAttachmentProcessing
    include ActivityPubMediaHandler
    include ActivityPubVisibilityHelper
    include ActivityPubHelper
    include ActivityPubUtilityHelpers

    def initialize
      @web_finger_service = WebFingerService.new
    end

    def resolve_remote_account(query)
      return nil unless account_query?(query)

      begin
        actor_data = @web_finger_service.fetch_actor_data(query)
        return nil unless actor_data

        create_actor_from_data(actor_data)
      rescue StandardError => e
        Rails.logger.warn "リモートアカウント解決エラー: #{e.message}"
        nil
      end
    end

    def search_domain_accounts(domain, offset: 0, limit: 20)
      return [] unless domain_query?(domain)

      accounts = []

      # 既存のローカルデータベースから検索
      existing_accounts = Actor.where(domain: domain)
                               .where(local: false)
                               .order(updated_at: :desc)
                               .offset(offset)
                               .limit([limit, 40].min)
      accounts.concat(existing_accounts)

      # 最初のページでアカウント数が少ない場合のみリモートから発見を試行
      if offset.zero? && accounts.length < limit
        remote_accounts = discover_remote_domain_accounts(domain)
        accounts.concat(remote_accounts)
      end

      accounts.uniq(&:id).take(limit)
    end

    def discover_remote_domain_accounts(domain)
      return [] if domain.blank?

      discovered_accounts = []

      # 1. インスタンス情報からユーザを発見
      discovered_accounts.concat(fetch_instance_directory(domain))

      # 2. よく知られたアカウントを試す
      discovered_accounts.concat(try_common_usernames(domain))

      discovered_accounts.uniq(&:id).take(10)
    rescue StandardError => e
      Rails.logger.warn "ドメインアクター発見エラー (#{domain}): #{e.message}"
      []
    end

    def resolve_remote_status(url)
      return nil unless url_query?(url)

      begin
        response = fetch_activitypub_object(url)
        return nil unless response

        activitypub_id = response['id']
        return nil unless activitypub_id

        existing_object = ActivityPubObject.find_by(ap_id: activitypub_id)
        return existing_object if existing_object

        create_remote_object(response)
      rescue StandardError => e
        Rails.logger.warn "リモート投稿解決エラー: #{e.message}"
        nil
      end
    end

    def resolve_remote_status_for_pinned(url)
      return nil unless url_query?(url)

      begin
        response = fetch_activitypub_object(url)
        return nil unless response

        activitypub_id = response['id']
        return nil unless activitypub_id

        existing_object = ActivityPubObject.find_by(ap_id: activitypub_id)
        return existing_object if existing_object

        create_remote_object(response, is_pinned_only: true)
      rescue StandardError => e
        Rails.logger.warn "ピン留め投稿解決エラー: #{e.message}"
        nil
      end
    end

    private

    def create_actor_from_data(data)
      allowed_types = %w[Person Service]
      return nil unless allowed_types.include?(data['type'])

      existing_actor = Actor.find_by(ap_id: data['id'])
      return existing_actor if existing_actor

      # ActorFetcherを使用してemoji処理も含めて作成
      actor_fetcher = ActorFetcher.new
      actor_fetcher.create_actor_from_data(data['id'], data)
    rescue StandardError => e
      Rails.logger.error "アクター作成エラー: #{e.message}"
      nil
    end

    def create_actor_record(data, username, domain)
      Actor.create!(
        username: username,
        domain: domain,
        display_name: data['name'],
        note: data['summary'],
        ap_id: data['id'],
        inbox_url: data['inbox'],
        outbox_url: data['outbox'],
        followers_url: data['followers'],
        following_url: data['following'],
        featured_url: data['featured'],
        public_key: data.dig('publicKey', 'publicKeyPem'),
        local: false,
        locked: data['manuallyApprovesFollowers'] || false,
        bot: data['type'] == 'Service',
        discoverable: data['discoverable'] || false,
        raw_data: data.to_json,
        fields: extract_fields_from_attachments(data).to_json,
        actor_type: data['type']
      )
    end

    def create_remote_object(data, is_pinned_only: false)
      return nil unless data['type'] == 'Note'

      actor = resolve_actor_for_object(data)
      return nil unless actor

      remote_id = Letter::Snowflake.generate
      create_activity_pub_object(data, actor, remote_id, is_pinned_only: is_pinned_only)
    rescue StandardError => e
      Rails.logger.error "リモートオブジェクト作成エラー: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      nil
    end

    def resolve_actor_for_object(data)
      actor_uri = data['attributedTo']
      actor = Actor.find_by(ap_id: actor_uri)

      unless actor
        actor_fetcher = ActorFetcher.new
        actor = actor_fetcher.fetch_and_create(actor_uri)
      end

      actor
    end

    def create_activity_pub_object(data, actor, remote_id, is_pinned_only: false)
      object = ActivityPubObject.create!(
        id: remote_id,
        ap_id: data['id'],
        object_type: data['type'],
        actor: actor,
        content: data['content'],
        content_plaintext: strip_html_tags(data['content']),
        summary: data['summary'],
        published_at: Time.zone.parse(data['published']),
        visibility: determine_visibility(data),
        raw_data: data.to_json,
        local: false,
        is_pinned_only: is_pinned_only
      )

      handle_media_attachments(object, data)
      object
    end

    def account_query?(query)
      AccountIdentifier.account_query?(query)
    end

    def domain_query?(query)
      AccountIdentifier.domain_query?(query)
    end

    def url_query?(query)
      query.match?(/^https?:\/\//)
    end

    def fetch_instance_directory(domain)
      return [] if domain.blank?

      begin
        uri = URI("https://#{domain}/api/v1/directory")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 5
        http.open_timeout = 3

        request = Net::HTTP::Get.new(uri.path)
        request['Accept'] = 'application/json'
        request['User-Agent'] = InstanceConfig.user_agent(:activitypub)

        response = http.request(request)
        return [] unless response.code == '200'

        directory_data = JSON.parse(response.body)
        return [] unless directory_data.is_a?(Array)

        directory_data.take(5).filter_map do |account_data|
          next unless account_data['username'] && account_data['acct']

          create_actor_from_directory_data(account_data, domain)
        end
      rescue StandardError
        []
      end
    end

    def try_common_usernames(domain)
      return [] if domain.blank?

      common_usernames = %w[admin info news announce bot moderator support]
      discovered = []

      common_usernames.each do |username|
        break if discovered.length >= 3

        account = try_resolve_account("#{username}@#{domain}")
        discovered << account if account
      end

      discovered
    end

    def create_actor_from_directory_data(account_data, domain)
      username = account_data['username']
      return nil unless username

      # 既存アクターをチェック
      existing_actor = Actor.find_by(username: username, domain: domain)
      return existing_actor if existing_actor

      # WebFingerで完全なプロフィールを取得
      try_resolve_account("#{username}@#{domain}")
    end

    def try_resolve_account(acct)
      return nil if acct.blank?

      begin
        actor_data = @web_finger_service.fetch_actor_data(acct)
        return nil unless actor_data

        create_actor_from_data(actor_data)
      rescue StandardError
        nil
      end
    end
  end
end
