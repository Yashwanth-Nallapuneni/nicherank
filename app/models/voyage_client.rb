require "net/http"
require "json"

# Minimal client for Voyage AI's embeddings API (https://docs.voyageai.com/reference/embeddings-api).
# Papers are embedded as "document", search boxes as "query"; both must use the same model and size.
class VoyageClient
  class Error < StandardError; end

  URL = URI("https://api.voyageai.com/v1/embeddings")
  MODEL = "voyage-4-lite"
  DIMENSIONS = 512
  RETRY_CODES = [429, 500, 502, 503, 504].freeze

  # Returns one Array of DIMENSIONS floats per text, in input order.
  def self.embed(texts, input_type:, timeout: 10, retries: 0)
    key = ENV["VOYAGE_API_KEY"].presence or raise Error, "VOYAGE_API_KEY is not set"
    body = { input: texts, model: MODEL, input_type: input_type, output_dimension: DIMENSIONS }.to_json
    attempt = 0
    begin
      attempt += 1
      response = post(body, key, timeout)
      code = response.code.to_i
      raise RetryableError, "Voyage HTTP #{code}" if RETRY_CODES.include?(code)
      raise Error, "Voyage HTTP #{code}: #{response.body.to_s[0, 200]}" unless code == 200

      JSON.parse(response.body).fetch("data").sort_by { |d| d["index"] }.map { |d| d["embedding"] }
    rescue RetryableError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, SocketError => e
      raise Error, e.message if attempt > retries

      sleep(2**attempt)
      retry
    rescue JSON::ParserError, KeyError => e
      raise Error, "Unexpected Voyage response: #{e.message}"
    end
  end

  def self.post(body, key, timeout)
    request = Net::HTTP::Post.new(URL, "Content-Type" => "application/json", "Authorization" => "Bearer #{key}")
    request.body = body
    Net::HTTP.start(URL.host, URL.port, use_ssl: true, open_timeout: timeout, read_timeout: timeout) do |http|
      http.request(request)
    end
  end
  private_class_method :post

  class RetryableError < Error; end
  private_constant :RetryableError
end
