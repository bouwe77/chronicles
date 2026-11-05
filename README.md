# Chronicles

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:9278`](http://localhost:9278) from your browser.

## Acceptance tests

`e2e/` holds Playwright journeys that use the app only in the browser: sign up, write a
story, play it, share it. Start the server first, then:

    cd e2e
    npm install
    npx playwright install chromium
    npx playwright test

They run against `localhost:9278` with the dev invite code, and read login links from
the dev mailbox. Each test makes its own user and deletes it afterwards. Set `E2E_URL`
and `E2E_INVITE_CODE` to test another server.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
