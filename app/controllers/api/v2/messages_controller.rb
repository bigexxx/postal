# frozen_string_literal: true

module API
  module V2
    class MessagesController < BaseController

      DIRECTIONS = %w[any to from].freeze
      DEFAULT_PER_PAGE = 50
      MAX_PER_PAGE = 100

      def index
        return unless validate_query_parameters

        query = {
          order: :timestamp,
          direction: "DESC",
          per_page: @per_page
        }
        if @direction == "any"
          query[:where_any] = { rcpt_to: @email, mail_from: @email }
        elsif @direction == "to"
          query[:where] = { rcpt_to: @email }
        else
          query[:where] = { mail_from: @email }
        end

        result = current_server.message_db.messages_with_pagination(@page, query)

        render json: {
          data: result[:records].map { |message| serialize_message(message) },
          pagination: {
            page: result[:page],
            per_page: result[:per_page],
            total: result[:total],
            total_pages: result[:total_pages]
          },
          filters: {
            email: @email,
            direction: @direction
          }
        }
      end

      private

      def validate_query_parameters
        @email = params[:email]
        unless @email.is_a?(String) && @email.length <= 255 && @email.match?(/\A[^@\s<>]+@[^@\s<>]+\z/)
          render_api_error(:unprocessable_content, "invalid_parameter",
                           "email must be a valid email address.", field: "email")
          return false
        end
        @email = @email.strip

        @direction = params.fetch(:direction, "any")
        unless @direction.is_a?(String) && DIRECTIONS.include?(@direction)
          render_api_error(:unprocessable_content, "invalid_parameter",
                           "direction must be one of: any, to, from.", field: "direction")
          return false
        end

        @page = positive_integer_parameter(:page, 1)
        return false unless @page

        @per_page = positive_integer_parameter(:per_page, DEFAULT_PER_PAGE, maximum: MAX_PER_PAGE)
        !!@per_page
      end

      def positive_integer_parameter(name, default, maximum: nil)
        value = params[name]
        return default if value.nil?

        integer = Integer(value, 10)
        if integer <= 0 || (maximum && integer > maximum)
          range = maximum ? "between 1 and #{maximum}" : "greater than 0"
          render_api_error(:unprocessable_content, "invalid_parameter",
                           "#{name} must be #{range}.", field: name.to_s)
          return
        end
        integer
      rescue ArgumentError, TypeError
        render_api_error(:unprocessable_content, "invalid_parameter",
                         "#{name} must be an integer.", field: name.to_s)
        nil
      end

      def serialize_message(message)
        {
          id: message.id,
          scope: message.scope,
          matched_on: matched_on(message),
          from: message.mail_from,
          to: message.rcpt_to,
          subject: message.subject,
          message_id: message.message_id,
          status: message.status,
          held: message.held == true,
          timestamp: iso8601_time(message.timestamp),
          last_delivery_attempt_at: iso8601_time(message.last_delivery_attempt),
          opened: message.loaded.present?,
          opened_at: timestamp_value(message.loaded),
          clicked: message.clicked.present?,
          clicked_at: timestamp_value(message.clicked)
        }
      end

      def matched_on(message)
        matches = []
        matches << "from" if message.mail_from&.casecmp?(@email)
        matches << "to" if message.rcpt_to&.casecmp?(@email)
        matches
      end

      def timestamp_value(value)
        value.present? ? iso8601_time(Time.zone.at(value)) : nil
      end

      def iso8601_time(value)
        value&.iso8601(6)
      end

    end
  end
end
