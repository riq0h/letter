# frozen_string_literal: true

module StatusParamsHandler
  extend ActiveSupport::Concern

  private

  def status_params
    permitted_params = permit_status_params
    transformed_params = transform_param_keys(permitted_params)
    process_reply_to_id(transformed_params)
    extract_media_and_mentions(transformed_params)
    apply_default_visibility(transformed_params)
    transformed_params
  end

  def permit_status_params
    params.permit(:status, :text, :in_reply_to_id, :sensitive, :spoiler_text, :visibility, :language,
                  media_ids: [], mentions: [],
                  poll: [:expires_in, :multiple, :hide_totals, { options: [] }])
  end

  def transform_param_keys(permitted_params)
    # textパラメータがある場合はstatusにマップ
    permitted_params['status'] = permitted_params['text'] if permitted_params['text'].present? && permitted_params['status'].blank?

    permitted_params.transform_keys do |key|
      case key
      when 'status', 'text' then 'content'
      when 'spoiler_text' then 'summary'
      when 'in_reply_to_id' then 'in_reply_to_ap_id'
      else key
      end
    end
  end

  def process_reply_to_id(transformed_params)
    return if transformed_params['in_reply_to_ap_id'].blank?

    reply_id = transformed_params['in_reply_to_ap_id']
    transformed_params['in_reply_to_ap_id'] = convert_reply_id_to_ap_id(reply_id)
  end

  def convert_reply_id_to_ap_id(reply_id)
    return reply_id if reply_id.start_with?('http')

    in_reply_to = ActivityPubObject.find_by(id: reply_id)
    in_reply_to&.ap_id
  end

  def extract_media_and_mentions(transformed_params)
    @media_ids = transformed_params.delete('media_ids')
    @mentions = transformed_params.delete('mentions')
    transformed_params.delete('poll')
  end

  def apply_default_visibility(transformed_params)
    transformed_params['visibility'] ||= 'public'
  end
end
