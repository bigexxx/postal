# frozen_string_literal: true

require "rails_helper"
require "rack/test"

RSpec.describe TrackingMiddleware do
  include Rack::Test::Methods

  let(:inner_app) { ->(_env) { [200, {}, ["inner"]] } }
  let(:app) { described_class.new(inner_app) }

  let(:server) { create(:server) }
  let(:message) do
    MessageFactory.incoming(server) do |_msg, mail|
      mail.html_part = Mail::Part.new do
        content_type "text/html; charset=UTF-8"
        body "<html><body>hi</body></html>"
      end
    end
  end

  def track_headers
    { "HTTP_X_POSTAL_TRACK_HOST" => "1" }
  end

  describe "GET /img/:server_token/:message_token (open tracking pixel)" do
    before do
      get "/img/#{server.token}/#{message.token}", {}, track_headers
    end

    it "returns the tracking pixel PNG" do
      expect(last_response.status).to eq 200
      expect(last_response.headers["Content-Type"]).to eq "image/png"
      expect(last_response.body.bytesize).to be > 0
    end

    it "records a load for the message" do
      # Re-fetch the message so loads are read fresh from the DB.
      reloaded = server.message_db.message(message.id)
      expect(reloaded.loads.size).to eq 1
    end
  end

  describe "GET /c/v1/:server_token/:message_token/:link_token/:url/:signature (signed click tracking)" do
    let(:destination_url) { "https://example.com/path?q=one&next=%2Ftwo#result" }
    let(:tracking_path) do
      Postal::TrackingUrl.generate(
        server_token: server.token,
        message_token: message.token,
        url: destination_url
      )
    end

    it "records the click and redirects to the signed destination" do
      allow(WebhookRequest).to receive(:trigger)

      get "/c/#{tracking_path}", {}, track_headers

      expect(last_response.status).to eq 307
      expect(last_response.headers["Location"]).to eq destination_url

      reloaded = server.message_db.message(message.id)
      expect(reloaded.clicks.size).to eq 1
      expect(reloaded.clicks.first.url).to eq destination_url
      expect(reloaded.clicked).not_to be_nil
      expect(WebhookRequest).to have_received(:trigger).with(
        server,
        "MessageLinkClicked",
        hash_including(url: destination_url, token: tracking_path.split("/")[-3])
      )
    end

    it "rejects a tampered destination without recording a click" do
      parts = tracking_path.split("/")
      parts[-2] = "#{parts[-2][0...-1]}#{parts[-2][-1] == 'A' ? 'B' : 'A'}"

      get "/c/#{parts.join('/')}", {}, track_headers

      expect(last_response.status).to eq 404
      expect(last_response.headers["Location"]).to be_nil
      expect(server.message_db.message(message.id).clicks).to be_empty
    end

    it "still redirects when the associated message has been removed" do
      removed_message_path = Postal::TrackingUrl.generate(
        server_token: server.token,
        message_token: "removed-message",
        url: destination_url
      )

      get "/c/#{removed_message_path}", {}, track_headers

      expect(last_response.status).to eq 307
      expect(last_response.headers["Location"]).to eq destination_url
    end
  end

  describe "GET /:server_token/:link_token (legacy click tracking)" do
    it "continues to resolve links generated before stateless tracking" do
      destination_url = "https://example.com/legacy"
      link_token = message.create_link(destination_url)

      get "/#{server.token}/#{link_token}", {}, track_headers

      expect(last_response.status).to eq 307
      expect(last_response.headers["Location"]).to eq destination_url
    end
  end

  describe "GET /img/:server_token/:message_token?src=<url> (image proxy)" do
    let(:attacker_url) { "http://internal.example.com/secret" }

    before do
      stub_request(:get, attacker_url).to_return(status: 200, body: "internal-secret")
    end

    it "does not fetch the URL and returns 400" do
      get "/img/#{server.token}/#{message.token}", { src: attacker_url }, track_headers

      expect(last_response.status).to eq 400
      expect(WebMock).not_to have_requested(:get, attacker_url)
    end

    it "does not fetch the URL even when the message token is invalid" do
      get "/img/#{server.token}/nonexistent", { src: attacker_url }, track_headers

      expect(WebMock).not_to have_requested(:get, attacker_url)
    end
  end

  describe "when the track-host header is missing" do
    it "passes the request through to the inner app untouched" do
      get "/img/#{server.token}/#{message.token}"
      expect(last_response.body).to eq "inner"
    end
  end
end
