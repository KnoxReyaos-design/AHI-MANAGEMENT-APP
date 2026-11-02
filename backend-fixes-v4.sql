-- v4: tamper-evident audit trail. NOT executed. Review in staging first.
-- Each audit row stores the hash of the row before it, so editing, deleting or
-- re-ordering any past entry breaks every hash after it and verify_audit_chain() reports it.

alter table public.audit_events add column if not exists chain_seq bigint;
alter table public.audit_events add column if not exists prev_hash text;
alter table public.audit_events add column if not exists row_hash text;

create or replace function public.audit_row_hash(p_prev text, r public.audit_events)
returns text language sql stable as $$
  select encode(sha256(convert_to(
    coalesce(p_prev,'genesis')||'|'||r.chain_seq::text||'|'||coalesce(r.id::text,'')||'|'||
    coalesce(r.occurred_at::text,'')||'|'||coalesce(r.actor_user_id::text,'')||'|'||coalesce(r.actor_role,'')||'|'||
    coalesce(r.event_type,'')||'|'||coalesce(r.entity_schema,'')||'|'||coalesce(r.entity_table,'')||'|'||
    coalesce(r.entity_id::text,'')||'|'||coalesce(r.before_data::text,'')||'|'||coalesce(r.after_data::text,'')||'|'||
    coalesce(r.reason,''),'UTF8')),'hex')
$$;

-- one-time backfill of existing rows, oldest first
do $$
declare r public.audit_events; prev text := null; n bigint := 0;
begin
  for r in select * from public.audit_events where row_hash is null order by occurred_at, id loop
    n := n + 1; r.chain_seq := n; r.prev_hash := prev;
    r.row_hash := public.audit_row_hash(prev, r);
    update public.audit_events set chain_seq=r.chain_seq, prev_hash=r.prev_hash, row_hash=r.row_hash where id=r.id;
    prev := r.row_hash;
  end loop;
end $$;

create or replace function public.audit_chain_before_insert() returns trigger
language plpgsql as $$
declare last_row record;
begin
  perform pg_advisory_xact_lock(727001);
  select chain_seq,row_hash into last_row from public.audit_events order by chain_seq desc nulls last limit 1;
  new.chain_seq := coalesce(last_row.chain_seq,0)+1;
  new.prev_hash := last_row.row_hash;
  new.row_hash  := public.audit_row_hash(new.prev_hash, new);
  return new;
end $$;
drop trigger if exists audit_chain_ins on public.audit_events;
create trigger audit_chain_ins before insert on public.audit_events
  for each row execute function public.audit_chain_before_insert();

-- audit rows can never be changed or removed (created after the backfill above)
create or replace function public.audit_block_change() returns trigger
language plpgsql as $$ begin raise exception 'Audit entries cannot be edited or deleted'; end $$;
drop trigger if exists audit_no_change on public.audit_events;
create trigger audit_no_change before update or delete on public.audit_events
  for each row execute function public.audit_block_change();

-- verification: super admin and admin only
create or replace function public.verify_audit_chain() returns jsonb
language plpgsql security definer set search_path=public as $$
declare r public.audit_events; prev text := null; n bigint := 0; exp bigint := 0;
begin
  if not exists(select 1 from public.profiles p where p.user_id=auth.uid()
                and p.account_status='active' and p.role in ('super_admin','admin')) then
    raise exception 'Not allowed';
  end if;
  for r in select * from public.audit_events order by chain_seq nulls first, occurred_at loop
    n := n + 1; exp := exp + 1;
    if r.chain_seq is distinct from exp or r.prev_hash is distinct from prev
       or r.row_hash is distinct from public.audit_row_hash(prev, r) then
      return jsonb_build_object('ok',false,'checked',n,'first_bad_seq',exp,'first_bad_id',r.id::text);
    end if;
    prev := r.row_hash;
  end loop;
  return jsonb_build_object('ok',true,'checked',n);
end $$;
revoke all on function public.verify_audit_chain() from public, anon;
grant execute on function public.verify_audit_chain() to authenticated;
-- Limits: this detects changes made after the fact. Someone with direct database
-- owner access could rebuild the whole chain, so also keep a periodic off-site export.
