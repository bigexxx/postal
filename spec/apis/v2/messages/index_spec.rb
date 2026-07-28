# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Messages API v2", type: :request do
  describe "GET /api/v2/messages" do
    let(:server) { create(:server) }
    let(:credential) { create(:credential, server: server) }
    let(:headers) { { "X-Server-API-Key" => credential.key } }

    def create_message(server, from:, to:, subject: "An example message")
      MessageFactory.outgoing(server) do |message, mail|
        message.mail_from = from
        message.rcpt_to = to
        mail.subject = subject
      end
    end

    it "requires a server API key" do
      get "/api/v2/messages", params: { email: "user@acdn.uz" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq(
        "error" => {
          "code" => "authentication_required",
          "message" => "X-Server-API-Key is required."
        }
      )
    end

    it "rejects an invalid server API key" do
      get "/api/v2/messages",
          params: { email: "user@acdn.uz" },
          headers: { "X-Server-API-Key" => "invalid" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_api_key")
    end

    it "rejects credentials for a suspended server" do
      suspended_server = create(:server, :suspended)
      suspended_credential = create(:credential, server: suspended_server)

      get "/api/v2/messages",
          params: { email: "user@acdn.uz" },
          headers: { "X-Server-API-Key" => suspended_credential.key }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("server_suspended")
    end

    it "validates query parameters" do
      get "/api/v2/messages",
          params: { email: "not-an-email", direction: "sideways" },
          headers: headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body["error"]).to include(
        "code" => "invalid_parameter",
        "field" => "email"
      )

      get "/api/v2/messages",
          params: { email: "user@acdn.uz", direction: "sideways" },
          headers: headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body["error"]).to include(
        "code" => "invalid_parameter",
        "field" => "direction"
      )

      get "/api/v2/messages",
          params: { email: "user@acdn.uz", per_page: 101 },
          headers: headers

      expect(response).to have_http_status(422)
      expect(response.parsed_body["error"]).to include(
        "code" => "invalid_parameter",
        "field" => "per_page"
      )
    end

    it "returns exact sender and recipient matches newest first" do
      recipient_match = create_message(
        server,
        from: "notifications@acdn.uz",
        to: "user@acdn.uz",
        subject: "Recipient match"
      )
      sender_match = create_message(
        server,
        from: "user@acdn.uz",
        to: "support@acdn.uz",
        subject: "Sender match"
      )
      create_message(server, from: "other@acdn.uz", to: "someone@acdn.uz")
      recipient_match.update(timestamp: 1.hour.ago.to_f)
      sender_match.update(
        timestamp: 30.minutes.ago.to_f,
        status: "Sent",
        last_delivery_attempt: 29.minutes.ago.to_f,
        loaded: 20.minutes.ago.to_f,
        clicked: 10.minutes.ago.to_f
      )

      get "/api/v2/messages",
          params: { email: "user@acdn.uz" },
          headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["data"].map { |message| message["id"] }).to eq([sender_match.id, recipient_match.id])
      expect(body["data"].first).to include(
        "scope" => "outgoing",
        "matched_on" => ["from"],
        "from" => "user@acdn.uz",
        "to" => "support@acdn.uz",
        "subject" => "Sender match",
        "status" => "Sent",
        "held" => false,
        "opened" => true,
        "clicked" => true
      )
      expect(body["data"].first["timestamp"]).to be_present
      expect(body["data"].first["last_delivery_attempt_at"]).to be_present
      expect(body["data"].first["opened_at"]).to be_present
      expect(body["data"].first["clicked_at"]).to be_present
      expect(body["pagination"]).to eq(
        "page" => 1,
        "per_page" => 50,
        "total" => 2,
        "total_pages" => 1
      )
      expect(body["filters"]).to eq(
        "email" => "user@acdn.uz",
        "direction" => "any"
      )
    end

    it "can limit results to recipient or sender matches" do
      recipient_match = create_message(server, from: "sender@acdn.uz", to: "user@acdn.uz")
      sender_match = create_message(server, from: "user@acdn.uz", to: "recipient@acdn.uz")

      get "/api/v2/messages",
          params: { email: "user@acdn.uz", direction: "to" },
          headers: headers
      expect(response.parsed_body["data"].pluck("id")).to eq([recipient_match.id])

      get "/api/v2/messages",
          params: { email: "user@acdn.uz", direction: "from" },
          headers: headers
      expect(response.parsed_body["data"].pluck("id")).to eq([sender_match.id])
    end

    it "paginates results" do
      messages = 3.times.map do |index|
        message = create_message(
          server,
          from: "notifications@acdn.uz",
          to: "user@acdn.uz",
          subject: "Message #{index}"
        )
        message.update(timestamp: index.minutes.ago.to_f)
        message
      end

      get "/api/v2/messages",
          params: { email: "user@acdn.uz", page: 2, per_page: 2 },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].pluck("id")).to eq([messages.last.id])
      expect(response.parsed_body["pagination"]).to include(
        "page" => 2,
        "per_page" => 2,
        "total" => 3,
        "total_pages" => 2
      )
    end
  end
end
