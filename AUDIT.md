# AHI repair notes — 1 November 2026

## Reported issues addressed

1. **Client onboarding lacked the investment selection workflow.** The Clients screen now loads active investment categories and packages. Registration can create the client/account and optionally create its first investment using `create_client` followed by `create_client_investment`. The form asks for principal and start date, previews package rules and an indicative maturity estimate, and displays a clear partial-success error if the client was created but the investment RPC failed. The database remains authoritative for expected return and maturity.
2. **Archived clients still appeared active and their accounts remained open.** `archive_client` now sets `archived_at`, `archived_by`, `archive_reason`, and `client_status='inactive'`, closes the linked client account with `closed_at`, `closed_by`, and `close_reason`, increments row versions, and writes an audit event. Existing unresolved-investment protection remains. Archived clients cannot be archived again.
3. **Company proprietary assets were not actionable.** The Company Portfolio screen now includes a register from `company_investments`, with Open actions. Asset detail includes editable name/description/counterparty/status, a controlled close action, and shortcuts to transaction and valuation forms. Historical ledger and valuation records are retained; hard delete is intentionally not offered.
4. **Catalogue Edit controls were inert.** Category and package Edit actions now use the existing `update_investment_category` and `update_investment_package` RPCs with optimistic row-version checks and change reasons. Package return-method fields are conditionally cleared to satisfy the database's return-configuration constraints.
5. **PWA shell refresh.** Added 192px and 512px AHI emblem icons, referenced them in the manifest and precached them. Service-worker cache name was bumped to `ahi-shell-v3` so installed clients replace the old shell.

## Backend functions

- `archive_client(uuid,bigint,text)` — updated in the connected Supabase project. Requires `clients.archive`, blocks unresolved investments, closes the client account, marks the client inactive/archived and records an audit event.
- `update_company_investment(uuid,bigint,text,text,text,text,date,text)` — added in the connected Supabase project. Requires `company.manage`, validates name/status/reason, uses optimistic row-version checking, records an audit event and only permits authenticated execution. Closing/exiting/writing off automatically sets an end date if none is supplied.
- Existing catalogue update functions were verified and used; no schema change was made to categories or packages.

The corresponding SQL is in `backend-fixes.sql` for reference/recreation.

## Verification performed

- Queried live Supabase information schema and function signatures for relevant tables/RPCs.
- Confirmed `create_client`, `create_client_investment`, package/category create/update, archive and company update function signatures.
- Confirmed the new company update RPC is executable by `authenticated` and not by `anon`.
- Confirmed relevant package constraints, including valid return-method configuration, currency format, duration, and active/inactive status values.
- `node --check` on the application module and service worker: PASS.
- HTML parser: PASS.
- Manifest JSON parse: PASS.
- Local arithmetic check for fixed-percentage and simple-interest package previews: PASS.

## Not yet verified

- No live client or company financial records were created, changed, or archived as a test. Do not use production clients to test destructive workflows.
- No authenticated browser end-to-end test was completed in this session.
- Android installed-PWA cold start/offline behaviour remains to be tested on the user's device.
- Full security posture, all RLS policies and all other modules have not been re-audited in this repair pass.

## Operational cautions

- Client creation and initial investment creation are two RPC calls, not one database transaction. If the second call fails, the client/account remains created and the app reports that the investment was not created.
- A client cannot be archived while unresolved investments exist.
- Company investment close is a status transition; it does not erase financial history.
- The app must be deployed with the manifest, service worker and both icon files in the same site root as `index.html`.


## Follow-up repair — 1 November 2026

- Rechecked the current single-file application JavaScript with `node --check`: PASS. The previous parser error was not reproducible against the current working file.
- Rechecked the service-worker JavaScript with `node --check`: PASS.
- Revalidated `manifest.json` as JSON: PASS.
- Rebuilt the service worker as `ahi-shell-v5`. Navigation requests are network-first with a cached shell fallback; Supabase requests and non-GET requests are not intercepted or cached.
- Confirmed the login path uses the returned Auth session user, checks for an active staff profile, loads role permissions, and does not sign out a valid session when initial workspace rendering fails.

### Still unverified
- No authenticated browser session was available for an end-to-end sign-in test in this build pass. Therefore, login is improved and the source parses, but a successful live login is not claimed. If login still fails after deploying this build, the exact on-screen error is needed to distinguish invalid credentials, missing/inactive staff profile, and RLS/network failures.
- No production financial records or schema were changed in this follow-up pass.
