-- AHI v45 · Trade Station records (run ONCE in Supabase > SQL Editor, safe to re-run).
-- Simulated trading only. These tables never touch client balances, investments or payouts.
-- The app writes here automatically; until you run this file, trade results are kept on the device
-- and the Overview card says "Saved on this device only".

create table if not exists public.trade_station_account (
  user_id uuid primary key default auth.uid(),
  starting_balance_usd numeric(14,2) not null default 0,
  realized_pnl_usd numeric(14,2) not null default 0,
  floating_pnl_usd numeric(14,2) not null default 0,
  equity_usd numeric(14,2) not null default 0,
  open_positions int not null default 0,
  closed_trades int not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.trade_station_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  trade_key text not null,
  instrument text not null,
  direction text not null check (direction in ('buy','sell')),
  lots numeric(10,2),
  entry_price numeric(18,5),
  exit_reason text,
  realized_pnl_usd numeric(14,2) not null default 0,
  closed_at timestamptz not null default now(),
  unique (user_id, trade_key)
);

alter table public.trade_station_account enable row level security;
alter table public.trade_station_ledger enable row level security;

drop policy if exists tsa_select on public.trade_station_account;
drop policy if exists tsa_insert on public.trade_station_account;
drop policy if exists tsa_update on public.trade_station_account;
create policy tsa_select on public.trade_station_account for select to authenticated
  using (user_id = auth.uid() or private.has_permission('reports.read'));
create policy tsa_insert on public.trade_station_account for insert to authenticated
  with check (user_id = auth.uid());
create policy tsa_update on public.trade_station_account for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists tsl_select on public.trade_station_ledger;
drop policy if exists tsl_insert on public.trade_station_ledger;
drop policy if exists tsl_update on public.trade_station_ledger;
create policy tsl_select on public.trade_station_ledger for select to authenticated
  using (user_id = auth.uid() or private.has_permission('reports.read'));
create policy tsl_insert on public.trade_station_ledger for insert to authenticated
  with check (user_id = auth.uid());
create policy tsl_update on public.trade_station_ledger for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update on public.trade_station_account to authenticated;
grant select, insert, update on public.trade_station_ledger to authenticated;

-- ===== v47 additions (safe to re-run): full trade details, transfers and liquidations =====
alter table public.trade_station_ledger add column if not exists exit_price numeric(18,5);
alter table public.trade_station_ledger add column if not exists stop_loss numeric(18,5);
alter table public.trade_station_ledger add column if not exists take_profit_1 numeric(18,5);
alter table public.trade_station_ledger add column if not exists take_profit_2 numeric(18,5);
alter table public.trade_station_ledger add column if not exists opened_at timestamptz;
alter table public.trade_station_account add column if not exists transferred_out_usd numeric(14,2) not null default 0;
alter table public.trade_station_account add column if not exists liquidations int not null default 0;

create table if not exists public.trade_station_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  event_key text not null,
  event_type text not null check (event_type in ('transfer','liquidation')),
  amount_usd numeric(14,2) not null default 0,
  note text,
  created_at timestamptz not null default now(),
  unique (user_id, event_key)
);
alter table public.trade_station_events enable row level security;
drop policy if exists tse_select on public.trade_station_events;
drop policy if exists tse_insert on public.trade_station_events;
drop policy if exists tse_update on public.trade_station_events;
create policy tse_select on public.trade_station_events for select to authenticated
  using (user_id = auth.uid() or private.has_permission('reports.read'));
create policy tse_insert on public.trade_station_events for insert to authenticated
  with check (user_id = auth.uid());
create policy tse_update on public.trade_station_events for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on public.trade_station_events to authenticated;
