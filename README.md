# NicheRank

- Joon Ahn (sa3883)
- Anthony Chang (ac5985)
- Sai Suhruth Reddy Karri (sk5843)
- Yashwanth Sai Nallapuneni (yn2509)

[Live app](https://nicherank-app-98c2ccb29d98.herokuapp.com/) | [GitHub repository](https://github.com/Yashwanth-Nallapuneni/nicherank)

## Requirements

Ruby 3.3.12 and Bundler 2.5.22. Tests also require a running local PostgreSQL 17 server with pgvector and a user allowed to create databases and extensions.

Run all commands from the repository root. Run `bundle install` once before starting the app or tests.

## Run

Place the privately supplied `nicherank-main-readonly.env` in the repository root, then run:

```sh
export DATABASE_URL="$(sed -n 's/^DATABASE_URL=//p' nicherank-main-readonly.env)"
bin/rails server
```

Open http://localhost:3000.

## Test

These commands use your Mac username with no password and PostgreSQL on port 5434. Adjust `TEST_DATABASE_URL` if your local database settings differ.

```sh
unset DATABASE_URL
export TEST_DATABASE_URL="postgres://$(whoami)@127.0.0.1:5434/nicherank_test"
RAILS_ENV=test bundle exec rspec
RAILS_ENV=test bundle exec cucumber
```

