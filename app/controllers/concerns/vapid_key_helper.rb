# frozen_string_literal: true

module VapidKeyHelper
  extend ActiveSupport::Concern

  private

  def vapid_public_key
    raw_key = ENV['VAPID_PUBLIC_KEY'] || Rails.application.credentials.dig(:vapid, :public_key)
    return nil unless raw_key

    pem_data = Base64.decode64(raw_key)
    ec_key = OpenSSL::PKey::EC.new(pem_data)
    public_key_uncompressed = ec_key.public_key.to_bn.to_s(2)

    Base64.urlsafe_encode64(public_key_uncompressed).tr('=', '')
  end
end
