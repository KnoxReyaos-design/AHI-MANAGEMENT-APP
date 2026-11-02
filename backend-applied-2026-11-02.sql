-- AHI v18 backend changes applied to Supabase project aeaxkcebentrcdauksnf on 2026-11-02.
-- Re-application is safe for the permission cleanup and function definition.

begin;

-- Admin is read-only. Super Admin retains all existing write permissions.
delete from public.role_permission_overrides
where role = 'admin'
  and permission_key in (
    'clients.write','clients.profile.correct','clients.archive',
    'clients.accounts.manage','clients.duplicates.manage',
    'client_investments.write','client_financials.write','catalog.manage',
    'company.manage','permissions.manage','users.manage','settings.manage'
  );

delete from public.role_permissions
where role = 'admin'
  and permission_key in (
    'clients.write','clients.profile.correct','clients.archive',
    'clients.accounts.manage','clients.duplicates.manage',
    'client_investments.write','client_financials.write','catalog.manage',
    'company.manage','permissions.manage','users.manage','settings.manage'
  );

create or replace function public.create_client_onboarding(
  p_full_name text,
  p_phone text default null,
  p_phone_normalized text default null,
  p_email text default null,
  p_email_normalized text default null,
  p_address text default null,
  p_identity_reference text default null,
  p_registration_date date default current_date,
  p_notes text default null,
  p_package_id uuid default null,
  p_principal numeric default null,
  p_start_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_client record;
  v_investment_id uuid;
  v_entry_id uuid;
  v_currency text;
begin
  if v_actor is null or not exists (
    select 1 from public.profiles p
    where p.user_id=v_actor and p.role='super_admin' and p.account_status='active'
  ) then
    raise exception 'Only an active Super Admin may complete client onboarding' using errcode='42501';
  end if;

  select * into v_client from public.create_client(
    p_full_name,p_phone,p_phone_normalized,p_email,p_email_normalized,
    p_address,p_identity_reference,p_registration_date,p_notes
  );

  if p_package_id is not null then
    if p_principal is null or p_principal <= 0 or p_start_date is null then
      raise exception 'A positive principal and start date are required when an initial investment is selected';
    end if;
    select ip.currency_code into v_currency
      from public.investment_packages ip
     where ip.id=p_package_id and ip.package_status='active';
    if v_currency is null then raise exception 'Active investment package not found'; end if;
    v_investment_id := public.create_client_investment(
      v_client.client_id,p_package_id,p_principal,p_start_date
    );
    v_entry_id := public.record_client_investment_entry(
      v_investment_id,'contribution',p_principal,v_currency,p_start_date,
      'onboard-contribution-'||v_investment_id::text,null,
      'Initial contribution recorded during client onboarding'
    );
  elsif p_principal is not null and p_principal <> 0 then
    raise exception 'Select an investment package or leave the initial principal empty';
  end if;

  return jsonb_build_object(
    'client_id',v_client.client_id,
    'client_number',v_client.client_number,
    'account_number',v_client.account_number,
    'investment_id',v_investment_id,
    'contribution_entry_id',v_entry_id
  );
end;
$function$;

revoke all on function public.create_client_onboarding(text,text,text,text,text,text,text,date,text,uuid,numeric,date) from public, anon;
grant execute on function public.create_client_onboarding(text,text,text,text,text,text,text,date,text,uuid,numeric,date) to authenticated;

commit;
