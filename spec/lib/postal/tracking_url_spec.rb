# frozen_string_literal: true

require "rails_helper"

RSpec.describe Postal::TrackingUrl do
  let(:attributes) do
    {
      server_token: "server-token",
      message_token: "message-token",
      link_token: "link-token",
      url: "https://example.com/path?q=one&next=%2Ftwo#result"
    }
  end

  it "round trips a signed URL" do
    version, server_token, message_token, link_token, encoded_url, signature = described_class.generate(**attributes).split("/")

    expect(version).to eq "v1"
    expect(described_class.verify(
             server_token: server_token,
             message_token: message_token,
             link_token: link_token,
             encoded_url: encoded_url,
             signature: signature
           )).to eq attributes[:url]
  end

  it "rejects a modified destination URL" do
    _version, server_token, message_token, link_token, encoded_url, signature = described_class.generate(**attributes).split("/")
    encoded_url = "#{encoded_url[0...-1]}#{encoded_url[-1] == 'A' ? 'B' : 'A'}"

    expect(described_class.verify(
             server_token: server_token,
             message_token: message_token,
             link_token: link_token,
             encoded_url: encoded_url,
             signature: signature
           )).to be_nil
  end

  it "rejects a modified signature" do
    _version, server_token, message_token, link_token, encoded_url, signature = described_class.generate(**attributes).split("/")
    signature = "#{signature[0...-1]}#{signature[-1] == 'A' ? 'B' : 'A'}"

    expect(described_class.verify(
             server_token: server_token,
             message_token: message_token,
             link_token: link_token,
             encoded_url: encoded_url,
             signature: signature
           )).to be_nil
  end

  it "rejects signed non-HTTP URLs" do
    path = described_class.generate(**attributes.merge(url: "javascript:alert(1)"))
    _version, server_token, message_token, link_token, encoded_url, signature = path.split("/")

    expect(described_class.verify(
             server_token: server_token,
             message_token: message_token,
             link_token: link_token,
             encoded_url: encoded_url,
             signature: signature
           )).to be_nil
  end
end
