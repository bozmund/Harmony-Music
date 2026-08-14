# Windows Auth0 setup

Harmony uses the fixed Windows callback URL `harmonymusic://callback`.

In the Auth0 Dashboard, open the Native application used by Harmony and add
that exact value to both **Allowed Callback URLs** and **Allowed Logout URLs**.
Debug builds use `harmonymusic-dev://callback` instead, so add that too.
Save the application settings before trying to log in again.

**Allowed Callback URLs** additionally needs the sign-in landing page — one entry per scheme,
because Auth0 matches `redirect_uri` exactly:

```
https://harmony-resolver.duckdns.org/cloud/auth/windows/callback/harmonymusic
https://harmony-resolver.duckdns.org/cloud/auth/windows/callback/harmonymusic-dev
```

The scheme is the last **path segment**, not a query parameter. A query string would have to be
registered verbatim to survive Auth0's exact match, which is fragile and something Auth0's own
guidance steers away from.

These URLs are served by Harmony Cloud, so **sign-in on Windows fails with a callback mismatch until
that deployment is live and both URLs are registered.** Debug builds use the `-dev` one; release
builds use the other.

## Why the login tab stays open and the logout tab does not

Both flows open the system browser and come back over the custom scheme. Only
the logout tab closes itself, and that is the browser's doing, not the app's:
the logout URL redirects to `harmonymusic://callback` without ever committing a
page, and a tab with empty history is one Chrome and Edge close on their own
once they hand off to an external protocol handler.

A login tab always commits real pages — the Auth0 Universal Login form, and the
Google account chooser when `prompt=login` is sent — so no browser will close
it. A page cannot close itself either: `window.close()` is a no-op for any tab
the user did not open via script. **There is no setting, on our side or Auth0's,
that makes the login tab disappear.**

What we do instead is send Auth0 to the landing page above, which performs the
`harmonymusic://callback` handoff and then leaves the tab on a deliberate
"signed in, you can close this tab" end state rather than a stale login form.
It is served by Harmony Cloud (`WindowsAuthCallbackPage`, mapped unauthenticated
in `Program.cs`) and passed as `redirectUrl` from `Auth0Service.login()`. The
scheme rides in the query string because debug and release differ, and is
checked against an allowlist before it is written into a redirect.

`logout()` deliberately does **not** go through the page — routing it there
would give that tab a committed page and stop it closing itself.

The Windows installer registers the `harmonymusic` protocol for the current
user. For a local Flutter build, first build the app and then run:

```powershell
.\windows\register_auth0_protocol.ps1
```

To register a Release build instead, pass its executable path with
`-ExecutablePath`.
