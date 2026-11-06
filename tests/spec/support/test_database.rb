# Creates the local test database and loads Suhruth's frozen schema (data/db/postgres/schema.sql).
# Shared by RSpec and Cucumber; never runs against DATABASE_URL.
begin
  ActiveRecord::Base.connection.verify!
rescue ActiveRecord::NoDatabaseError
  ActiveRecord::Tasks::DatabaseTasks.create(ActiveRecord::Base.connection_db_config)
  ActiveRecord::Base.establish_connection
end
unless ActiveRecord::Base.connection.table_exists?(:papers)
  ActiveRecord::Base.connection.execute(File.read(Rails.root.join("data/db/postgres/schema.sql")))
end
