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

The current 52-school dataset is hosted by the Heroku app `nicherank-db`. With collaborator access, sign in using `heroku login`, then run:

```sh
export DATABASE_URL="$(heroku config:get DATABASE_URL --app nicherank-db)"
export PGOPTIONS="-c default_transaction_read_only=on"
bin/rails server
```

Open http://localhost:3000. `PGOPTIONS` makes these local preview sessions read-only; it does not change the database account's permissions. Keep database credentials out of Git. The older `nicherank-main-readonly.env` connects to the previous 10-school Neon dataset.

## Test

These commands use your Mac username with no password and PostgreSQL on port 5434. Adjust `TEST_DATABASE_URL` if your local database settings differ.

```sh
unset DATABASE_URL
unset PGOPTIONS
export TEST_DATABASE_URL="postgres://$(whoami)@127.0.0.1:5434/nicherank_test"
RAILS_ENV=test bundle exec rspec
RAILS_ENV=test bundle exec cucumber
```

The saved-institution Cucumber scenarios run in headless Chrome using Selenium.
Install Google Chrome (or Chromium) before running Cucumber. Selenium Manager
locates the browser and downloads a compatible driver on the first run, which
requires network access. Other scenarios continue to use the rack-test driver.
Bookmarks are stored only in the visitor's browser; they require JavaScript and
site storage, do not sync across browsers, and are removed with browser data.

## UI reference

The interface follows the [NicheRank Research Explorer](https://nicherank-research-explorer.wurtylex.chatgpt.site/) visual design while retaining the Rails app's search and ranking behavior. DM Sans is bundled locally under the [SIL Open Font License](app/assets/fonts/OFL.txt).

School logos for all 52 institutions in `data/db/data/manual/universities.csv` are bundled from official university websites; see [logo sources](docs/institution-logo-sources.txt). Institutions without a mapped logo use initials.
