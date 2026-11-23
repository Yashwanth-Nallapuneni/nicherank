# Creates the local test database and loads Suhruth's frozen schema (data/db/postgres/schema.sql)
# plus our additive semantic-search table (db/paper_embeddings.sql).
# Shared by RSpec and Cucumber. Refuses anything but a local test database, because an
# exported DATABASE_URL overrides config/database.yml and could point at the real data.
abort "Tests must run with RAILS_ENV=test (got #{Rails.env})." unless Rails.env.test?
test_host = ActiveRecord::Base.connection_db_config.host.to_s
unless %w[localhost 127.0.0.1 ::1].include?(test_host)
  abort "Refusing to run tests against non-local database host #{test_host.inspect}. Point TEST_DATABASE_URL at a local database."
end
begin
  ActiveRecord::Base.connection.verify!
rescue ActiveRecord::NoDatabaseError
  ActiveRecord::Tasks::DatabaseTasks.create(ActiveRecord::Base.connection_db_config)
  ActiveRecord::Base.establish_connection
end
unless ActiveRecord::Base.connection.table_exists?(:papers)
  ActiveRecord::Base.connection.execute(File.read(Rails.root.join("data/db/postgres/schema.sql")))
end
unless ActiveRecord::Base.connection.table_exists?(:venue_rankings)
  ActiveRecord::Base.connection.execute(File.read(Rails.root.join("data/db/postgres/venue_rankings.sql")))
end
unless ActiveRecord::Base.connection.table_exists?(:paper_embeddings)
  ActiveRecord::Base.connection.execute(File.read(Rails.root.join("db/paper_embeddings.sql")))
end

# Match the existing production table locally; never run this against Heroku.
unless ActiveRecord::Base.connection.table_exists?(:professor_embeddings)
  ActiveRecord::Base.connection.execute(<<~SQL)
    CREATE TABLE professor_embeddings (
      professor_id bigint PRIMARY KEY REFERENCES professors(id) ON DELETE CASCADE,
      embedding vector(512) NOT NULL,
      papers integer NOT NULL,
      computed_at timestamptz NOT NULL DEFAULT now()
    )
  SQL
end
