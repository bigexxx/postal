# frozen_string_literal: true

require "base64"
require "openssl"
require "securerandom"
require "uri"

module Postal
  class TrackingUrl

    VERSION = "v1"
    SIGNATURE_DIGEST = "SHA256"

    class << self

      def generate(server_token:, message_token:, url:, link_token: SecureRandom.alphanumeric(16))
        encoded_url = Base64.urlsafe_encode64(url, padding: false)
        signature = signature_for(server_token, message_token, link_token, encoded_url)
        "#{VERSION}/#{server_token}/#{message_token}/#{link_token}/#{encoded_url}/#{signature}"
      end

      def verify(server_token:, message_token:, link_token:, encoded_url:, signature:)
        expected_signature = signature_for(server_token, message_token, link_token, encoded_url)
        return unless secure_compare(signature, expected_signature)

        url = Base64.urlsafe_decode64(encoded_url)
        uri = URI.parse(url)
        return unless uri.is_a?(URI::HTTP) && uri.host

        url
      rescue ArgumentError, URI::InvalidURIError
        nil
      end

      private

      def signature_for(server_token, message_token, link_token, encoded_url)
        digest = OpenSSL::HMAC.digest(
          SIGNATURE_DIGEST,
          signing_key,
          [VERSION, server_token, message_token, link_token, encoded_url].join("\0")
        )
        Base64.urlsafe_encode64(digest, padding: false)
      end

      def signing_key
        @signing_key ||= OpenSSL::HMAC.digest(
          SIGNATURE_DIGEST,
          Postal.signer.private_key.to_der,
          "postal-tracking-url-signing-key\0#{VERSION}"
        )
      end

      def secure_compare(value, expected)
        return false unless value.is_a?(String)
        return false unless value.bytesize == expected.bytesize

        ActiveSupport::SecurityUtils.secure_compare(value, expected)
      end

    end

  end
end
