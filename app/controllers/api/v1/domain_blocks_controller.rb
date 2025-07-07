# frozen_string_literal: true

module Api
  module V1
    class DomainBlocksController < Api::BaseController
      before_action :doorkeeper_authorize!

      # GET /api/v1/domain_blocks
      def index
        return render_authentication_required unless current_user

        domain_blocks = paginated_domain_blocks
        domains = domain_blocks.pluck(:domain)

        add_pagination_headers(domain_blocks) if domain_blocks.any?
        render json: domains
      end

      def paginated_domain_blocks
        domain_blocks = base_domain_blocks_query
        apply_pagination_to_domain_blocks(domain_blocks)
      end

      def base_domain_blocks_query
        current_user.domain_blocks
                    .order(created_at: :desc)
                    .limit(limit_param)
      end

      def apply_pagination_to_domain_blocks(domain_blocks)
        return apply_max_id_filter(domain_blocks) if params[:max_id].present?
        return apply_since_id_filter(domain_blocks) if params[:since_id].present?
        return apply_min_id_filter(domain_blocks) if params[:min_id].present?

        domain_blocks
      end

      def apply_max_id_filter(domain_blocks)
        domain_blocks.where(id: ...(params[:max_id]))
      end

      def apply_since_id_filter(domain_blocks)
        domain_blocks.where('id > ?', params[:since_id])
      end

      def apply_min_id_filter(domain_blocks)
        domain_blocks.where('id > ?', params[:min_id])
      end

      # POST /api/v1/domain_blocks
      def create
        return render_authentication_required unless current_user

        domain = normalized_domain_param
        return render_validation_failed('Domain parameter is required') if domain.blank?

        create_domain_block(domain)
      end

      def normalized_domain_param
        params[:domain]&.strip&.downcase
      end

      def create_domain_block(domain)
        current_user.domain_blocks.find_or_create_by!(domain: domain)
        render json: {}, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: 'Validation failed', details: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue StandardError => e
        Rails.logger.error "Domain block creation failed: #{e.message}"
        render_operation_failed('Block domain')
      end

      # DELETE /api/v1/domain_blocks
      def destroy
        return render_authentication_required unless current_user

        domain = normalized_domain_param
        return render_validation_failed('Domain parameter is required') if domain.blank?

        domain_block = current_user.domain_blocks.find_by(domain: domain)

        if domain_block
          domain_block.destroy
          render json: {}
        else
          render_not_found('Domain')
        end
      end

      private

      def limit_param
        [params[:limit]&.to_i || 40, 200].min
      end

      def add_pagination_headers(collection)
        return unless collection.respond_to?(:first) && collection.respond_to?(:last)

        links = build_pagination_links(collection)
        response.headers['Link'] = links.join(', ') if links.any?
      end

      def build_pagination_links(collection)
        links = []
        links << build_next_link(collection.first) if collection.first
        links << build_prev_link(collection.last) if collection.last
        links
      end

      def build_next_link(first_item)
        %(<#{request.url}?max_id=#{first_item.id}>; rel="next")
      end

      def build_prev_link(last_item)
        %(<#{request.url}?min_id=#{last_item.id}>; rel="prev")
      end
    end
  end
end
