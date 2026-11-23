require "rails_helper"

RSpec.describe VoyageClient do
  let(:http) { instance_double(Net::HTTP) }

  def respond_with(code, body)
    response = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request).and_return(response)
  end

  around do |example|
    old = ENV["VOYAGE_API_KEY"]
    ENV["VOYAGE_API_KEY"] = "test-key"
    example.run
  ensure
    ENV["VOYAGE_API_KEY"] = old
  end

  it "sends the model, size and input type and returns vectors in input order" do
    respond_with(200, { data: [{ index: 1, embedding: [0.2] }, { index: 0, embedding: [0.1] }] }.to_json)

    expect(described_class.embed(%w[first second], input_type: "query")).to eq([[0.1], [0.2]])
    expect(http).to have_received(:request) do |request|
      body = JSON.parse(request.body)
      expect(body).to include("model" => "voyage-4-lite", "output_dimension" => 512, "input_type" => "query",
                              "input" => %w[first second])
      expect(request["Authorization"]).to eq("Bearer test-key")
    end
  end

  it "raises VoyageClient::Error on a client error" do
    respond_with(401, '{"detail":"bad key"}')
    expect { described_class.embed(["x"], input_type: "query") }.to raise_error(VoyageClient::Error, /401/)
  end

  it "retries rate-limited requests before giving up" do
    respond_with(429, "slow down")
    allow(described_class).to receive(:sleep)

    expect { described_class.embed(["x"], input_type: "document", retries: 2) }.to raise_error(VoyageClient::Error)
    expect(http).to have_received(:request).exactly(3).times
  end

  it "raises without an API key instead of calling the API" do
    ENV["VOYAGE_API_KEY"] = ""
    allow(Net::HTTP).to receive(:start)
    expect { described_class.embed(["x"], input_type: "query") }.to raise_error(VoyageClient::Error, /VOYAGE_API_KEY/)
    expect(Net::HTTP).not_to have_received(:start)
  end

  it "raises instead of returning a short result when Voyage sends fewer embeddings than texts" do
    respond_with(200, { data: [] }.to_json)
    expect { described_class.embed(["x"], input_type: "query") }.to raise_error(VoyageClient::Error, /0 embeddings for 1/)
  end

  it "retries a dropped connection and then succeeds" do
    response = instance_double(Net::HTTPResponse, code: "200", body: { data: [{ index: 0, embedding: [0.5] }] }.to_json)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    calls = 0
    allow(http).to receive(:request) { (calls += 1) == 1 ? raise(EOFError) : response }
    allow(described_class).to receive(:sleep)

    expect(described_class.embed(["x"], input_type: "query", retries: 1)).to eq([[0.5]])
  end
end
