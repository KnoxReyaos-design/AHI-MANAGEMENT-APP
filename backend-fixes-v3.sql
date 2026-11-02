-- =====================================================================
-- backend-fixes-v3.sql   (NOT EXECUTED by the author - no database access)
-- Review in a STAGING project first. Do not run in production untested.
-- Adds custom company investment types (screen 3, Investment type builder).
-- Screens 1, 2 and 4 need NO database change.
-- =====================================================================
create table if not exists public.company_investment_types (
  id uuid primary key default gen_random_uuid(),
  type_name text not null check (length(trim(type_name))>0),
  fields text[] not null default '{}',
  custom_fields text[] not null default '{}',
  return_basis text not null default 'net_invested' check (return_basis in ('net_invested','net_deployed')),
  projection_method text not null default 'fixed' check (projection_method in ('fixed','income','manual')),
  default_growth numeric not null default 12 check (default_growth>=0),
  valuation_reminder_days int not null default 30 check (valuation_reminder_days>0),
  locked boolean not null default false,   -- set true once an investment uses the type
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create unique index if not exists company_investment_types_name_uq on public.company_investment_types (lower(type_name));
alter table public.company_investment_types enable row level security;
create policy company_investment_types_read on public.company_investment_types
  for select to authenticated using (private.has_permission('company.read'));
-- no insert/update/delete policies: writes go only through the RPC below.

create or replace function public.create_company_investment_type(
  p_name text, p_fields text[], p_custom_fields text[], p_return_basis text,
  p_projection_method text, p_default_growth numeric, p_valuation_reminder_days int
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_id uuid;
begin
  if auth.uid() is null or not private.has_permission('company.manage') then
    raise exception 'Not authorized' using errcode='42501';
  end if;
  if nullif(trim(p_name),'') is null then raise exception 'Type name is required'; end if;
  insert into public.company_investment_types
    (type_name,fields,custom_fields,return_basis,projection_method,default_growth,valuation_reminder_days)
  values (trim(p_name),coalesce(p_fields,'{}'),coalesce(p_custom_fields,'{}'),p_return_basis,
          p_projection_method,p_default_growth,p_valuation_reminder_days)
  returning id into v_id;
  return v_id;
end $function$;
revoke all on function public.create_company_investment_type(text,text[],text[],text,text,numeric,int) from public, anon;
grant execute on function public.create_company_investment_type(text,text[],text[],text,text,numeric,int) to authenticated;
-- TODO (next step): add company_investments.custom_type_id and lock the type when first used.

-- =====================================================================
-- Calculation rules (screen 7): what counts as made / lost, valuation
-- reminder days, year start. Single settings row. Changes are audited.
-- =====================================================================
create table if not exists public.company_calc_rules (
  id int primary key default 1 check (id=1),
  made_types text[] not null default '{income,dividend,interest,rent,realised_gain}',
  lost_types text[] not null default '{expense,fee,tax,realised_loss,write_down,write_off}',
  stale_days int not null default 30 check (stale_days>0),
  year_start_month int not null default 1 check (year_start_month between 1 and 12),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);
insert into public.company_calc_rules(id) values (1) on conflict do nothing;
alter table public.company_calc_rules enable row level security;
create policy company_calc_rules_read on public.company_calc_rules
  for select to authenticated using (private.has_permission('company.read'));

create or replace function public.set_company_calc_rules(
  p_made text[], p_lost text[], p_stale_days int, p_year_start int, p_reason text
) returns void
language plpgsql security definer set search_path=''
as $function$
declare v_before jsonb;
begin
  if auth.uid() is null or not private.has_permission('company.manage') then
    raise exception 'Not authorized' using errcode='42501';
  end if;
  if nullif(trim(p_reason),'') is null then raise exception 'A reason is required'; end if;
  if p_made && p_lost then raise exception 'A type cannot be both made and lost'; end if;
  select to_jsonb(r) into v_before from public.company_calc_rules r where id=1;
  update public.company_calc_rules
     set made_types=p_made, lost_types=p_lost, stale_days=p_stale_days,
         year_start_month=p_year_start, updated_at=now(), updated_by=auth.uid()
   where id=1;
  insert into public.audit_events(actor_user_id,actor_role,event_type,entity_schema,entity_table,entity_id,before_data,after_data,reason)
  select auth.uid(),pr.role,'COMPANY_RULES_UPDATED','public','company_calc_rules','1',v_before,
         jsonb_build_object('made_types',p_made,'lost_types',p_lost,'stale_days',p_stale_days,'year_start_month',p_year_start),p_reason
    from public.profiles pr where pr.user_id=auth.uid();
end $function$;
revoke all on function public.set_company_calc_rules(text[],text[],int,int,text) from public, anon;
grant execute on function public.set_company_calc_rules(text[],text[],int,int,text) to authenticated;
