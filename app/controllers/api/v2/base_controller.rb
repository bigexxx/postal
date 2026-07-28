# frozen_string_literal: true

module API
  module V2
    class BaseController < ActionController::API

      skip_before_action :set_browser_id
      skip_before_action :validate_auth_session
      skip_around_action :touch_auth_session

      before_action :authenticate_server

      private

      attr_reader :current_credential, :current_server

      def authenticate_server
        key = request.headers["X-Server-API-Key"]
        return render_api_error(:unauthorized, "authentication_required", "X-Server-API-Key is required.") if key.blank?

        credential = Credential.find_by(type: "API", key: key)
        return render_api_error(:unauthorized, "invalid_api_key", "The server API key is not valid.") unless credential

        if credential.server.suspended?
          return render_api_error(:forbidden, "server_suspended", "The server is suspended.")
        end

        credential.use
        @current_credential = credential
        @current_server = credential.server
      end

      def render_api_error(status, code, message, field: nil)
        error = { code: code, message: message }
        error[:field] = field if field
        render json: { error: error }, status: status
      end

    end
  end
end
