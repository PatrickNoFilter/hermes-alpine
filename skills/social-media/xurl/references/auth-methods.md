# X API Auth Methods — Quick Comparison

| Method | Browser Needed? | Read/Write? | Tokens | Persistence |
|--------|----------------|-------------|--------|-------------|
| **OAuth 2.0 PKCE** | ✅ Yes (localhost:8080) | Full R+W | Client ID + Secret; auto-refresh | Permanent until revoked |
| **OAuth 1.0a** | ❌ No | Full R+W | Consumer Key/Secret + Access Token/Secret | Permanent until revoked |
| **App-only (Bearer)** | ❌ No | Read-only (public data) | Bearer Token | Permanent until revoked |

## When to use each

**OAuth 2.0 PKCE** — Default/recommended. Auto-refreshing tokens, broad scopes. Requires a browser on the same machine (localhost:8080 callback). Use on laptops, desktops, or any machine with X11/display.

⚠️ **Callback URL must be HTTPS.** X's developer portal now requires `https://` callback URLs in some regions/app tiers. Set `https://localhost/callback` if `http://localhost:8080/callback` is rejected. Also set a Website URL in the portal (Settings → App info) — this is a separate mandatory field.

**OAuth 1.0a** — Best for headless environments (server, SSH, Termux, Docker without display). Tokens are generated from the developer portal (no browser needed for the CLI setup). Same API surface as OAuth 2.0. Setup:
1. User goes to X Developer Portal → app → "Keys and tokens" → scroll to "Access Token and Secret"
2. Generate or copy Access Token + Access Token Secret
3. `xurl auth oauth1 --consumer-key ... --consumer-secret ... --access-token ... --token-secret ...`
4. `xurl auth default APP_NAME`

**App-only (Bearer Token)** — Read-only, no user context. Good for: searching public posts, looking up users, reading public timelines/tweets. Cannot: post, reply, like, DM, follow. Setup:

⚠️ **Limitation: account-specific 401s.** The same Bearer Token may return `401` on some user lookups and `CreditsDepleted` or `200` on others. This is not a token problem — the endpoint restricts visibility per-account. Accounts that are private, suspended, deactivated, or have user-level restrictions cannot be resolved via app-only auth even for basic `/2/users/by/username/` lookups. Use OAuth 1.0a/2.0 (user-context auth) for those. Test against a known-public account (e.g. `elonmusk`) to verify the token works, before debugging account-specific failures.

Setup:
1. Copy Bearer Token from developer portal
2. `xurl auth app --bearer-token "AAAA...token"`
3. `xurl auth default APP_NAME`

## Bearer Token URL-encoding pitfall

Bearer Tokens from the X portal often contain URL-encoded characters:
- `%2B` → `+` 
- `%3D` → `=`

When using `curl -H "Authorization: Bearer $TOKEN"`, the shell may expand or corrupt these characters. **Safer alternatives:**
- Use `xurl auth app --bearer-token "..."` (no shell interpolation)
- Use Python: `urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})`
- Write token to a temp file and use `curl -H @/tmp/headers.txt`

## Checking current auth

```bash
xurl auth status
```

The default app (marked with `▸`) must have valid credentials. If `default` shows `(no credentials)` but a named app has `bearer: ✓` or `oauth2: ✓`, run:
```bash
xurl auth default NAMED_APP
```
