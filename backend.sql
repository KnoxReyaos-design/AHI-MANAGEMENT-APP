-- AHI WORKSPACE v37 · delete investment PACKAGE that clients have invested in (run ONCE in Supabase > SQL Editor, safe to re-run).
-- Category delete needs nothing new (it already works in your database).
--   * Package with no client investments -> permanently deleted.
--   * Package clients have invested in   -> super admin only; hidden from the catalog and new investments;
--                                           the package keeps its name and numbers so client investment IDs never change.
--   * Active investments still inside    -> super admin override with a written reason.

alter table public.investment_packages add column if not exists deleted_at timestamptz;
alter table public.investment_packages add column if not exists deleted_by uuid;
alter table public.investment_packages add column if not exists deleted_reason text;
alter table public.investment_categories add column if not exists deleted_at timestamptz;
alter table public.investment_categories add column if not exists deleted_by uuid;
alter table public.investment_categories add column if not exists deleted_reason text;

drop function if exists public.delete_investment_package(uuid, text);
drop function if exists public.delete_investment_category(uuid, text);

create or replace function public.delete_investment_package(p_id uuid, p_reason text default null, p_override boolean default false)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_before jsonb; v_total int; v_active int; v_paid int; v_super boolean; v_reason text := nullif(trim(p_reason), '');
begin
  if auth.uid() is null or not private.has_permission('catalog.manage') then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  select to_jsonb(p) into v_before from public.investment_packages p where p.id = p_id and p.deleted_at is null;
  if v_before is null then raise exception 'Package not found'; end if;

  select count(*),
         count(*) filter (where ci.investment_status not in ('fully_paid_closed', 'cancelled')),
         count(*) filter (where ci.investment_status = 'fully_paid_closed')
    into v_total, v_active, v_paid
    from public.client_investments ci where ci.package_id = p_id;

  if v_total = 0 then
    delete from public.investment_packages where id = p_id;
    insert into public.audit_events(actor_user_id, actor_role, event_type, entity_schema, entity_table, entity_id, before_data, after_data, reason)
    select auth.uid(), pr.role, 'INVESTMENT_PACKAGE_DELETED', 'public', 'investment_packages', p_id::text, v_before, null, coalesce(v_reason, 'Deleted in app')
      from public.profiles pr where pr.user_id = auth.uid();
    return jsonb_build_object('mode', 'deleted', 'total', 0, 'active', 0, 'paid', 0);
  end if;

  select exists (select 1 from public.profiles where user_id = auth.uid() and role = 'super_admin' and account_status = 'active') into v_super;
  if not v_super then
    raise exception 'Clients have already invested in this package, so only the super admin can remove it. Set it to inactive instead.' using errcode = '42501';
  end if;
  if v_active > 0 and not coalesce(p_override, false) then
    raise exception '% client investment(s) in this package are still active. The super admin must confirm the override.', v_active using errcode = '22023';
  end if;
  if v_active > 0 and v_reason is null then
    raise exception 'A reason is required to override' using errcode = '22023';
  end if;

  update public.investment_packages
     set deleted_at = now(), deleted_by = auth.uid(), deleted_reason = coalesce(v_reason, 'All client investments paid'),
         package_status = 'inactive', row_version = row_version + 1
   where id = p_id;
  insert into public.audit_events(actor_user_id, actor_role, event_type, entity_schema, entity_table, entity_id, before_data, after_data, reason)
  select auth.uid(), pr.role, 'INVESTMENT_PACKAGE_DELETED', 'public', 'investment_packages', p_id::text, v_before, null,
         case when v_active > 0 then 'OVERRIDE (' || v_active || ' active, ' || v_paid || ' paid client investments): ' || v_reason
              else coalesce(v_reason, 'All ' || v_paid || ' client investment(s) paid') end
    from public.profiles pr where pr.user_id = auth.uid();
  return jsonb_build_object('mode', 'retired', 'total', v_total, 'active', v_active, 'paid', v_paid);
end $$;
grant execute on function public.delete_investment_package(uuid, text, boolean) to authenticated;

-- Category delete (already present in your database; repeated here so one file fully matches the app)
create or replace function public.delete_investment_category(p_id uuid, p_reason text default null, p_override boolean default false)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  v_before jsonb; v_pk jsonb; v_total int; v_active int; v_paid int;
  v_super boolean; v_reason text := nullif(trim(p_reason), ''); v_name text;
begin
  if auth.uid() is null or not private.has_permission('catalog.manage') then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  select to_jsonb(c) into v_before from public.investment_categories c where c.id = p_id and c.deleted_at is null;
  if v_before is null then raise exception 'Category not found'; end if;
  select coalesce(jsonb_agg(to_jsonb(ip)), '[]'::jsonb) into v_pk from public.investment_packages ip where ip.category_id = p_id;
  select count(*),
         count(*) filter (where ci.investment_status not in ('fully_paid_closed', 'cancelled')),
         count(*) filter (where ci.investment_status = 'fully_paid_closed')
    into v_total, v_active, v_paid
    from public.client_investments ci
   where ci.category_id = p_id
      or exists (select 1 from public.investment_packages ip where ip.id = ci.package_id and ip.category_id = p_id);
  if v_total = 0 then
    delete from public.investment_packages where category_id = p_id;
    delete from public.investment_categories where id = p_id;
    insert into public.audit_events(actor_user_id, actor_role, event_type, entity_schema, entity_table, entity_id, before_data, after_data, reason)
    select auth.uid(), pr.role, 'INVESTMENT_CATEGORY_DELETED', 'public', 'investment_categories', p_id::text,
           v_before || jsonb_build_object('packages', v_pk), null, coalesce(v_reason, 'Deleted in app')
      from public.profiles pr where pr.user_id = auth.uid();
    return jsonb_build_object('mode', 'deleted', 'total', 0, 'active', 0, 'paid', 0);
  end if;
  select exists (select 1 from public.profiles where user_id = auth.uid() and role = 'super_admin' and account_status = 'active') into v_super;
  if not v_super then
    raise exception 'Clients have already invested under this category, so only the super admin can remove it. Set it to inactive instead.' using errcode = '42501';
  end if;
  if v_active > 0 and not coalesce(p_override, false) then
    raise exception '% client investment(s) under this category are still active. The super admin must confirm the override.', v_active using errcode = '22023';
  end if;
  if v_active > 0 and v_reason is null then
    raise exception 'A reason is required to override' using errcode = '22023';
  end if;
  v_name := left((v_before->>'name'), 70) || ' (deleted ' || to_char(now() at time zone 'Africa/Lusaka', 'DD/MM/YYYY') || ')';
  update public.investment_packages set package_status = 'inactive' where category_id = p_id and package_status <> 'inactive';
  update public.investment_categories
     set deleted_at = now(), deleted_by = auth.uid(), deleted_reason = coalesce(v_reason, 'All client investments paid'),
         category_status = 'inactive', name = v_name, product_code = null, row_version = row_version + 1
   where id = p_id;
  insert into public.audit_events(actor_user_id, actor_role, event_type, entity_schema, entity_table, entity_id, before_data, after_data, reason)
  select auth.uid(), pr.role, 'INVESTMENT_CATEGORY_DELETED', 'public', 'investment_categories', p_id::text,
         v_before || jsonb_build_object('packages', v_pk), null,
         case when v_active > 0 then 'OVERRIDE (' || v_active || ' active, ' || v_paid || ' paid client investments): ' || v_reason
              else coalesce(v_reason, 'All ' || v_paid || ' client investment(s) paid') end
    from public.profiles pr where pr.user_id = auth.uid();
  return jsonb_build_object('mode', 'retired', 'total', v_total, 'active', v_active, 'paid', v_paid);
end $$;
grant execute on function public.delete_investment_category(uuid, text, boolean) to authenticated;
