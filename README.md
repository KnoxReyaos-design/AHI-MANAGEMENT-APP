# AHI Management PWA

Mobile-first internal management and financial record-keeping application for Aspire Hands Innovation.

## Deploy
Upload `index.html`, `manifest.json`, `sw.js`, `icon-192.png`, and `icon-512.png` together into the GitHub Pages site root. Preserve filenames and serve over HTTPS. After deployment, open the site in your phone browser, refresh once, then close and reopen it. The service worker uses a new cache version (`ahi-shell-v5`) and never intercepts Supabase requests. For an installed PWA that still shows an old screen, remove the old home-screen shortcut, clear that site’s browser storage/cache, reopen the live URL, and install it again.

## Company proprietary investments
The Company Portfolio form is asset-class aware. Select Foreign Exchange / Multi-Asset Trading, Stocks, Bonds, Real Estate, Agriculture / Farming, Rental Property, or Other. The remaining fields change to match the selected asset class.

- **Foreign exchange:** FX-only or multi-asset mandate, instruments/symbols, execution market, broker/platform, capital and mandate notes. Multi-asset symbols can include currencies, indices, commodities and crypto.
- **Stocks:** instrument type, exchange, ticker, issuer, share quantity, purchase price per share, nominal value, estimated annual value and dividend assumptions.
- **Bonds:** government, corporate, municipal, property, private or infrastructure bonds; issuer, face value, quantity, purchase price, coupon, frequency, issue and maturity dates and credit rating.
- **Real estate / rental property:** residential, commercial, industrial, land or mixed-use; property location, unit count, acquisition price, per-unit rent, annual rent, vacancy, renovation, water, electricity, maintenance and insurance/rates/taxes.
- **Farming:** activity type, project, location, land size, product, capacity, annual revenue and operating costs.
- **Other:** user-defined class and subtype, counterparty, quantity, acquisition value, expected annual income and costs. Choosing real estate under Other exposes rental/property details.

Asset-specific data is stored in `company_investments.investment_details` as JSONB. The investment's currency remains on the parent record; financial ledger entries and valuations remain separate actual records. Estimates in the asset profile are assumptions, not posted income or cash balances.

## Backend changes
`backend-fixes.sql` records the SQL changes applied to the connected Supabase project:
- Client archiving closes the client account, marks the client inactive and records an audit event, subject to unresolved-investment and permission checks.
- Company investment update RPC preserves optimistic concurrency and audit history.
- `company_investments.investment_details` stores class-specific structured attributes.
- New 16-argument create and 9-argument update RPC overloads accept JSONB details. Older RPC overloads remain for backward compatibility. New overloads are executable by authenticated users only and enforce `company.manage`.

## Important accounting distinction
Asset-specific annual rent, dividend, coupon and income fields are planning assumptions. They do not create actual ledger entries. Record actual receipts and expenses through the company transaction ledger and record market/management values through valuations. Currency totals must remain separate.

## Security
The frontend uses the Supabase publishable key. Never place a service-role or secret key in this project. Verify staff permissions and RLS before using actual client funds.

## Login troubleshooting
- Sign in with the email/password belonging to an active row in `profiles` for the same Supabase Auth user. A Supabase Auth account alone is not sufficient for staff access.
- If credentials are accepted but the workspace does not open, check that the profile has `account_status = active` and that the user can read their own profile and role permission rows under RLS.
- The app intentionally does not sign out a valid user merely because a dashboard query fails. Use the page retry control after a workspace data error.
- Never share passwords, access tokens, or secret/service-role keys when reporting an error. Share only the exact on-screen error text.
