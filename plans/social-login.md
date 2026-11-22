# Social login

Status: library chosen (2026-11-22), not built. Providers: Google and GitHub.

## What it is

Another way for invited users to log in, next to the email link. It doesn't let new
people in: Chronicles stays invite-only. The callback finds the existing user by
**verified** email and calls `UserAuth.log_in_user/2`. No account with that email means
no login.

## Decision: Assent

We compared [Assent](https://github.com/pow-auth/assent) and
[Ueberauth](https://github.com/ueberauth/ueberauth) (with `ueberauth_google` and
`ueberauth_github`).

| Topic | Winner | Why |
|---|---|---|
| Providers | Equal | Both have Google and GitHub. Assent has all providers in one package, plus generic OpenID Connect. |
| Setup | Ueberauth, slightly | A plug does the redirect and the `state` check. With Assent we write those two steps, about 30–40 lines from its README. |
| Security | **Assent** | Assent returns `email_verified` for both providers. Ueberauth's `Auth.Info` has no such field; `ueberauth_github` takes the primary email without checking `verified`. |
| Maintenance | Assent, slightly | Assent releases steadily (0.4.0, Nov 2026) but has one main maintainer. Ueberauth's Google and GitHub packages were last released in 2023, and it was moving them into one repo in Oct 2026 with a breaking change not yet released. |
| Popularity | Ueberauth, slightly | More tutorials and examples. Recent downloads are about equal; `ash_authentication` uses Assent. |
| Fit | **Assent** | Assent uses `Req`, which we have. Ueberauth's packages use `oauth2`, which brings in Tesla, against `AGENTS.md`. |

Assent wins on the two topics that matter most here: the verified-email check, which
keeps email matching safe, and the `Req` rule.

## When we build it

- Log in only when `user["email_verified"] == true`. Give the same error for every
  failure, so nobody learns which emails have accounts.
- Assent 0.4 needs Elixir 1.18. The production image must use 1.18 or newer.
- Matching by email breaks when a user's provider email differs from their Chronicles
  email, or after they change their email here. If that matters, add a
  `user_identities` table (`provider`, `provider_uid`, `user_id`) and look users up by
  `provider_uid` after the first login.
- Facts above were checked on Hex and GitHub on 2026-11-22. Check them again before
  building.
