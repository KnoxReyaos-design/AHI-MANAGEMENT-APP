
-- Asset-specific company investment data. The UI stores class-specific fields
-- as structured JSONB instead of forcing unrelated fields into one generic form.
alter table public.company_investments
 add column if not exists investment_details jsonb not null default '{}'::jsonb;

-- New overload preserves the original 15-argument RPC for backward compatibility.
create or replace function public.create_company_investment(
 p_name text, p_asset_type text, p_custom_asset_type text, p_broker text,
 p_currency text, p_start_date date, p_description text, p_issuer text,
 p_face_value numeric, p_coupon_rate numeric, p_coupon_frequency text,
 p_bond_maturity_date date, p_quantity numeric, p_average_unit_cost numeric,
 p_property_location text, p_investment_details jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_id uuid; v_details jsonb:=coalesce(p_investment_details,'{}'::jsonb);
begin
 if auth.uid() is null or not private.has_permission('company.manage') then
  raise exception 'Not authorized' using errcode='42501';
 end if;
 if nullif(trim(p_name),'') is null then raise exception 'Investment name is required'; end if;
 if p_asset_type not in ('forex','stocks','bonds','real_estate','farming','rental_property','custom') then
  raise exception 'Invalid investment type';
 end if;
 if jsonb_typeof(v_details)<>'object' then raise exception 'Investment details must be an object'; end if;
 if p_asset_type='forex' and not (v_details ? 'market_scope') then raise exception 'Select the foreign exchange market scope'; end if;
 if p_asset_type='stocks' and nullif(v_details->>'stock_type','') is null then raise exception 'Select the stock instrument type'; end if;
 if p_asset_type='bonds' and nullif(v_details->>'bond_type','') is null then raise exception 'Select the bond type'; end if;
 if p_asset_type='real_estate' and nullif(v_details->>'property_type','') is null then raise exception 'Select the property type'; end if;
 if p_asset_type='custom' and nullif(trim(p_custom_asset_type),'') is null then raise exception 'Specify the other investment type'; end if;
 insert into public.company_investments(
 investment_name,asset_type,custom_asset_type,broker_or_counterparty,currency_code,
 start_date,description,issuer,face_value,coupon_rate,coupon_frequency,bond_maturity_date,
 quantity,average_unit_cost,property_location,investment_details,created_by,updated_by
 ) values (
 trim(p_name),p_asset_type,nullif(trim(p_custom_asset_type),''),nullif(trim(p_broker),''),
 upper(trim(p_currency)),p_start_date,nullif(trim(p_description),''),nullif(trim(p_issuer),''),
 p_face_value,p_coupon_rate,p_coupon_frequency,p_bond_maturity_date,p_quantity,p_average_unit_cost,
 nullif(trim(p_property_location),''),v_details,auth.uid(),auth.uid()
 ) returning id into v_id;
 return v_id;
end;
$function$;
revoke all on function public.create_company_investment(text,text,text,text,text,date,text,text,numeric,numeric,text,date,numeric,numeric,text,jsonb) from public,anon;
grant execute on function public.create_company_investment(text,text,text,text,text,date,text,text,numeric,numeric,text,date,numeric,numeric,text,jsonb) to authenticated;

-- New overload updates asset-specific JSONB and retains optimistic concurrency/audit.
create or replace function public.update_company_investment(
 p_id uuid, p_expected_version bigint, p_name text, p_description text,
 p_broker text, p_status text, p_end_date date, p_reason text,
 p_investment_details jsonb
) returns bigint
language plpgsql security definer set search_path=''
as $function$
declare v_actor uuid:=auth.uid(); v_version bigint; v_before jsonb; v_end_date date;
begin
 if v_actor is null or not private.has_permission('company.manage') then
  raise exception 'Not authorized to manage company investments' using errcode='42501';
 end if;
 if nullif(trim(p_name),'') is null or length(trim(p_name))<2 or length(trim(p_name))>140 then
  raise exception 'Investment name must be between 2 and 140 characters';
 end if;
 if p_status not in ('planned','active','partially_realised','matured','exited','written_down','written_off','closed') then
  raise exception 'Invalid company investment status';
 end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Change reason is required'; end if;
 if p_investment_details is not null and jsonb_typeof(p_investment_details)<>'object' then
  raise exception 'Investment details must be a JSON object';
 end if;
 select jsonb_build_object('investment_name',investment_name,'investment_status',investment_status,'end_date',end_date,'investment_details',investment_details)
 into v_before from public.company_investments where id=p_id for update;
 if not found then raise exception 'Company investment not found'; end if;
 v_end_date:=case when p_status in ('closed','exited','written_off') then coalesce(p_end_date,current_date) else p_end_date end;
 update public.company_investments
 set investment_name=trim(p_name),description=nullif(trim(p_description),''),
     broker_or_counterparty=nullif(trim(p_broker),''),investment_status=p_status,
     end_date=v_end_date,investment_details=coalesce(p_investment_details,investment_details),
     updated_by=v_actor,updated_at=now(),row_version=row_version+1
 where id=p_id and row_version=p_expected_version returning row_version into v_version;
 if v_version is null then raise exception 'Investment changed elsewhere; reload before saving' using errcode='40001'; end if;
 insert into public.audit_events(actor_user_id,actor_role,event_type,entity_schema,entity_table,entity_id,before_data,after_data,reason)
 select v_actor,pr.role,'COMPANY_INVESTMENT_UPDATED','public','company_investments',p_id::text,
        v_before,jsonb_build_object('investment_name',trim(p_name),'investment_status',p_status,'end_date',v_end_date,'investment_details',coalesce(p_investment_details,v_before->'investment_details'),'row_version',v_version),trim(p_reason)
 from public.profiles pr where pr.user_id=v_actor;
 return v_version;
end;
$function$;
revoke all on function public.update_company_investment(uuid,bigint,text,text,text,text,date,text,jsonb) from public,anon;
grant execute on function public.update_company_investment(uuid,bigint,text,text,text,text,date,text,jsonb) to authenticated;
