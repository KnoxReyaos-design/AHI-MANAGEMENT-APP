AHI CLIENT MANAGEMENT — v18

Files for GitHub Pages root:
- index.html
- sw.js
- manifest.json
- logo.jpg
- icon-192.png
- icon-512.png

Supabase project: aeaxkcebentrcdauksnf

Backend changes applied:
- Admin role has read-only permissions (clients, investments, catalog, reports).
- Super Admin retains its existing write permissions.
- public.create_client_onboarding(...) now saves the client, optional initial investment, and initial contribution in one database transaction.
- Existing payout RPC already allows a pre-maturity payout only for an active Super Admin. It continues to enforce funded principal, matching currency, idempotency, and outstanding-obligation limits. No actual payment is initiated.

The SQL file is retained as a record of the backend change. It is safe to re-run for the permission cleanup and onboarding function.

Deployment:
1. Upload all six website files to the repository root, replacing old files.
2. Commit and wait for GitHub Pages to publish.
3. Open the site in Chrome and refresh. If an older shell persists, close the installed PWA and reopen it; the new service-worker cache version is ahi-client-v18.
4. Sign in as the Super Admin to create clients, investments, contributions and payouts.
5. Admin and Read Only accounts can view records but cannot make changes. The database enforces this through role permissions and the onboarding/payout functions.

Limitations / verification:
- Static JavaScript, service-worker and manifest checks are run on this package.
- The live database schema and function definitions were inspected. No real client data was created or modified during verification.
- An authenticated end-to-end browser test was not possible in this environment. Verify one test client and investment in a controlled test dataset before relying on the workflow.
- The app records transactions only. It does not transfer funds, initiate payments or verify that money changed hands.
- Offline mode only provides cached app-shell assets. Data operations require an internet connection.
