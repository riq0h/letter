# frozen_string_literal: true

module Api
  module V1
    class DomainBlocksController < Api::BaseController
      include ApiPagination
      before_action :doorkeeper_authorize!
      before_action :require_user!

      # GET /api/v1/domain_blocks
      def index
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
        apply_collection_pagination(domain_blocks, 'domain_blocks')
      end

      # POST /api/v1/domain_blocks
      def create
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
        render_validation_error(e.record)
      rescue StandardError => e
        Rails.logger.error "Domain block creation failed: #{e.message}"
        render_operation_failed('Block domain')
      end

      # DELETE /api/v1/domain_blocks
      def destroy
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
