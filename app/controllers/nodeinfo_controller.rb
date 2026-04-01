# frozen_string_literal: true

class NodeinfoController < ApplicationController
  skip_before_action :verify_authenticity_token

  # GET /nodeinfo/2.1
  # NodeInfo 2.1仕様実装
  def show
    render json: Rails.cache.fetch('nodeinfo:2.1', expires_in: 15.minutes) { build_nodeinfo_response },
           content_type: 'application/json; charset=utf-8'
  end

  private

  def build_nodeinfo_response
    domain = Rails.application.config.activitypub.domain

    {
      version: '2.1',
      software: {
        name: 'letter',
        version: '0.1',
        homepage: 'https://github.com/riq0h/letter',
        repository: 'https://github.com/riq0h/letter'
      },
      protocols: ['activitypub'],
      services: {
        outbound: [],
        inbound: []
      },
      usage: calculate_usage_stats,
      openRegistrations: false,
      metadata: build_metadata.merge(
        domain: domain,
        baseUrl: "#{Rails.application.config.activitypub.protocol}://#{domain}"
      )
    }
  end

  def calculate_usage_stats
    {
      users: calculate_user_stats,
      localPosts: ActivityPubObject.local.notes.count,
      localComments: ActivityPubObject.local.where.not(in_reply_to_ap_id: nil).count
    }
  end

  def calculate_user_stats
    {
      total: Actor.local.count,
      activeMonth: Actor.local.where('updated_at > ?', 1.month.ago).count,
      activeHalfyear: Actor.local.where('updated_at > ?', 6.months.ago).count
    }
  end

  def build_metadata
    base_metadata.merge(
      features: supported_features,
      instance: instance_metadata
    )
  end

  def base_metadata
    {
      nodeName: InstanceConfig.get('instance_name') || Rails.application.config.instance_name,
      nodeDescription: InstanceConfig.get('instance_description') || Rails.application.config.instance_description,
      maintainer: maintainer_info,
      langs: Rails.application.config.activitypub.supported_locales,
      tosUrl: nil,
      privacyPolicyUrl: nil,
      impressumUrl: nil,
      repositoryUrl: 'https://github.com/riq0h/letter',
      feedbackUrl: 'https://github.com/riq0h/letter/issues',
      disableRegistration: true,
      disableLocalTimeline: false,
      disableGlobalTimeline: false,
      emailRequiredForSignup: false,
      enableHcaptcha: false,
      enableRecaptcha: false,
      maxNoteTitleLength: 100,
      maxNoteTextLength: Rails.application.config.activitypub.character_limit,
      maxCwLength: 500,
      enableEmail: false,
      enableServiceWorker: false,
      proxyAccountName: nil,
      themeColor: '#1f2937',
      iconUrl: instance_icon_url
    }
  end

  def maintainer_info
    {
      name: InstanceConfig.get('instance_maintainer') || Rails.application.config.instance_maintainer,
      email: InstanceConfig.get('instance_contact_email') || Rails.application.config.instance_contact_email
    }
  end

  def supported_features
    %w[
      activitypub
      federation
      long_posts
      media_attachments
      mentions
      hashtags
    ]
  end

  def instance_icon_url
    base_url = "#{Rails.application.config.activitypub.protocol}://#{Rails.application.config.activitypub.domain}"
    icon_path = Rails.public_path.join('instance.png')
    File.exist?(icon_path) ? "#{base_url}/instance.png" : nil
  end

  def instance_metadata
    {
      maxAccounts: Rails.application.config.activitypub.max_accounts,
      currentAccounts: Actor.local.count,
      motto: InstanceConfig.get('instance_description') || Rails.application.config.instance_description
    }
  end
end
