# Semantic search embeddings. Run against the real database with its DATABASE_URL and VOYAGE_API_KEY set:
#   bin/rails embeddings:create_table   # additive table + HNSW index (db/paper_embeddings.sql)
#   bin/rails embeddings:status
#   DRY_RUN=1 bin/rails embeddings:backfill   # token estimate, no API calls
#   bin/rails embeddings:backfill             # embeds only papers that have no embedding yet; safe to re-run
namespace :embeddings do
  desc "Create the paper_embeddings table and index if missing"
  task create_table: :environment do
    ActiveRecord::Base.connection.execute(Rails.root.join("db/paper_embeddings.sql").read)
    puts "paper_embeddings is ready"
  end

  desc "Show how many papers have embeddings"
  task status: :environment do
    total = Paper.count
    done = ActiveRecord::Base.connection.select_value("SELECT count(*) FROM paper_embeddings").to_i
    puts "#{done} of #{total} papers embedded (#{total - done} missing)"
  end

  desc "Embed every paper that has no embedding yet (BATCH, THREADS, LIMIT, DRY_RUN)"
  task backfill: :environment do
    batch = Integer(ENV.fetch("BATCH", 128))      # texts per API request
    threads = Integer(ENV.fetch("THREADS", 6))    # parallel API requests per round
    limit = ENV["LIMIT"]&.to_i                     # stop after this many papers (for a trial run)
    conn = ActiveRecord::Base.connection
    missing = Paper.where("NOT EXISTS (SELECT 1 FROM paper_embeddings e WHERE e.paper_id = papers.id)")

    if ENV["DRY_RUN"]
      chars = missing.sum("length(title) + coalesce(length(left(abstract, #{PaperEmbedding::MAX_ABSTRACT})), 0)")
      puts "#{missing.count} papers to embed, about #{(chars / 4.0 / 1e6).round(1)}M tokens"
      next
    end

    done = 0
    started = Time.now
    loop do
      round = missing.order(:id).limit([batch * threads, limit && (limit - done)].compact.min)
                     .pluck(:id, :title, :abstract)
      break if round.empty?

      vectors = round.each_slice(batch).map do |slice|
        Thread.new do
          VoyageClient.embed(slice.map { |_, title, abstract| PaperEmbedding.text_for(title, abstract) },
                             input_type: "document", timeout: 60, retries: 6)
        end
      end.flat_map(&:value)

      conn.raw_connection.exec_params(<<~SQL, [PG::TextEncoder::Array.new.encode(round.map(&:first)), PG::TextEncoder::Array.new.encode(vectors.map { |v| "[#{v.join(',')}]" }), VoyageClient::MODEL])
        INSERT INTO paper_embeddings (paper_id, embedding, model)
        SELECT id, emb::vector, $3 FROM unnest($1::bigint[], $2::text[]) AS t(id, emb)
        ON CONFLICT (paper_id) DO NOTHING
      SQL
      done += round.size
      rate = done / [Time.now - started, 1].max
      puts format("%d embedded (%.0f/s)", done, rate)
      break if limit && done >= limit
    end
    puts "Finished: #{done} papers embedded this run"
  end
end
