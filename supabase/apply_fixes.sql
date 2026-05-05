-- Canonical production fix set for an existing Supabase database.
-- Run this after schema.sql when you need to upgrade a live database.

create extension if not exists pgcrypto;

alter table public.business_profile
  add column if not exists delivery_order_threshold numeric(10, 2) not null default 20000,
  add column if not exists delivery_extra_order_percent numeric(10, 4) not null default 0.20;

alter table public.users
  add column if not exists email text,
  add column if not exists account_discount_percentage numeric(5, 2) not null default 0;

alter table public.categories
  add column if not exists image_url text not null default '';

update public.users
set account_discount_percentage = 0
where account_discount_percentage is null;

update public.users
set
  name = nullif(trim(name), ''),
  phone = nullif(trim(phone), ''),
  email = nullif(trim(email), '')
where
  (name is not null and name <> trim(name))
  or (phone is not null and phone <> trim(phone))
  or (email is not null and email <> trim(email));

with ranked_user_names as (
  select
    id,
    row_number() over (
      partition by lower(btrim(name))
      order by created_at asc nulls last, id asc
    ) as duplicate_rank
  from public.users
  where name is not null and btrim(name) <> ''
)
update public.users as u
set name = concat(btrim(u.name), '-', left(replace(u.id::text, '-', ''), 6))
from ranked_user_names as ranked
where u.id = ranked.id
  and ranked.duplicate_rank > 1;

with ranked_user_emails as (
  select
    id,
    row_number() over (
      partition by lower(btrim(email))
      order by created_at asc nulls last, id asc
    ) as duplicate_rank
  from public.users
  where email is not null and btrim(email) <> ''
)
update public.users as u
set email = null
from ranked_user_emails as ranked
where u.id = ranked.id
  and ranked.duplicate_rank > 1;

with ranked_user_phones as (
  select
    id,
    row_number() over (
      partition by btrim(phone)
      order by created_at asc nulls last, id asc
    ) as duplicate_rank
  from public.users
  where phone is not null and btrim(phone) <> ''
)
update public.users as u
set phone = null
from ranked_user_phones as ranked
where u.id = ranked.id
  and ranked.duplicate_rank > 1;

create unique index if not exists users_name_normalized_unique_idx
  on public.users ((lower(btrim(name))))
  where name is not null and btrim(name) <> '';

create unique index if not exists users_email_normalized_unique_idx
  on public.users ((lower(btrim(email))))
  where email is not null and btrim(email) <> '';

create unique index if not exists users_phone_normalized_unique_idx
  on public.users ((btrim(phone)))
  where phone is not null and btrim(phone) <> '';

create or replace function public.assert_user_identity_available(
  target_user_id uuid,
  target_name text default null,
  target_phone text default null,
  target_email text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_name text := nullif(trim(coalesce(target_name, '')), '');
  normalized_phone text := nullif(trim(coalesce(target_phone, '')), '');
  normalized_email text := nullif(trim(coalesce(target_email, '')), '');
begin
  if normalized_name is not null and exists (
    select 1
    from public.users
    where lower(trim(name)) = lower(normalized_name)
      and id <> target_user_id
  ) then
    raise exception 'Username is already taken.';
  end if;

  if normalized_phone is not null and exists (
    select 1
    from public.users
    where trim(phone) = normalized_phone
      and id <> target_user_id
  ) then
    raise exception 'Phone number is already linked to another account.';
  end if;

  if normalized_email is not null and exists (
    select 1
    from public.users
    where lower(trim(email)) = lower(normalized_email)
      and id <> target_user_id
  ) then
    raise exception 'Email address is already linked to another account.';
  end if;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_name text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'name', '')), '');
  normalized_phone text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone', new.phone::text, '')), '');
  normalized_email text := nullif(trim(coalesce(new.email, new.raw_user_meta_data ->> 'email', '')), '');
  normalized_location text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'location', '')), '');
  normalized_role text := case
    when lower(coalesce(new.email, new.raw_user_meta_data ->> 'email', '')) = 'paffpro01@gmail.com' then 'admin'
    else 'client'
  end;
begin
  perform public.assert_user_identity_available(
    new.id,
    normalized_name,
    normalized_phone,
    normalized_email
  );

  insert into public.users (id, name, phone, email, location, role)
  values (
    new.id,
    normalized_name,
    normalized_phone,
    normalized_email,
    normalized_location,
    normalized_role
  )
  on conflict (id) do update
    set
      name = coalesce(excluded.name, public.users.name),
      phone = coalesce(excluded.phone, public.users.phone),
      email = coalesce(excluded.email, public.users.email),
      location = coalesce(excluded.location, public.users.location),
      role = case
        when lower(coalesce(excluded.email, public.users.email, '')) = 'paffpro01@gmail.com' then 'admin'
        else coalesce(excluded.role, public.users.role)
      end;
  return new;
end;
$$;

create or replace function public.ensure_current_user_profile()
returns public.users
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  auth_user record;
  normalized_name text;
  normalized_phone text;
  normalized_email text;
  normalized_location text;
  normalized_role text;
  ensured_user public.users;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated.';
  end if;

  select id, email, phone, raw_user_meta_data
  into auth_user
  from auth.users
  where id = auth.uid();

  if not found then
    raise exception 'Authenticated user was not found.';
  end if;

  normalized_name := nullif(trim(coalesce(auth_user.raw_user_meta_data ->> 'name', '')), '');
  normalized_phone := nullif(trim(coalesce(auth_user.raw_user_meta_data ->> 'phone', auth_user.phone::text, '')), '');
  normalized_email := nullif(trim(coalesce(auth_user.email, auth_user.raw_user_meta_data ->> 'email', '')), '');
  normalized_location := nullif(trim(coalesce(auth_user.raw_user_meta_data ->> 'location', '')), '');
  normalized_role := case
    when lower(coalesce(auth_user.email, auth_user.raw_user_meta_data ->> 'email', '')) = 'paffpro01@gmail.com' then 'admin'
    else 'client'
  end;

  perform public.assert_user_identity_available(
    auth.uid(),
    normalized_name,
    normalized_phone,
    normalized_email
  );

  insert into public.users (id, name, phone, email, location, role)
  values (
    auth.uid(),
    normalized_name,
    normalized_phone,
    normalized_email,
    normalized_location,
    normalized_role
  )
  on conflict (id) do update
    set
      name = coalesce(excluded.name, public.users.name),
      phone = coalesce(excluded.phone, public.users.phone),
      email = coalesce(excluded.email, public.users.email),
      location = coalesce(excluded.location, public.users.location),
      role = case
        when lower(coalesce(excluded.email, public.users.email, '')) = 'paffpro01@gmail.com' then 'admin'
        else coalesce(excluded.role, public.users.role)
      end
  returning * into ensured_user;

  return ensured_user;
end;
$$;

create or replace function public.sync_auth_user_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_name text;
  current_phone text;
  normalized_email text := nullif(trim(coalesce(new.email, '')), '');
begin
  select name, phone
  into current_name, current_phone
  from public.users
  where id = new.id;

  perform public.assert_user_identity_available(
    new.id,
    current_name,
    current_phone,
    normalized_email
  );

  update public.users
  set email = normalized_email
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

drop trigger if exists on_auth_user_email_updated on auth.users;
create trigger on_auth_user_email_updated
after update of email on auth.users
for each row
when (new.email is distinct from old.email)
execute function public.sync_auth_user_email();

grant execute on function public.ensure_current_user_profile() to anon, authenticated;
grant execute on function public.handle_new_user() to anon, authenticated;
grant execute on function public.sync_auth_user_email() to anon, authenticated;

create table if not exists public.order_payment_history (
  id bigint generated by default as identity primary key,
  order_id bigint not null references public.orders(id) on delete cascade,
  payment_amount numeric(10, 2) not null check (payment_amount > 0),
  previous_paid_amount numeric(10, 2) not null default 0,
  new_paid_amount numeric(10, 2) not null default 0,
  previous_status text not null default 'Pending',
  new_status text not null default 'Pending',
  remaining_balance numeric(10, 2) not null default 0,
  recorded_by uuid references public.users(id) on delete set null,
  note text,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create index if not exists order_payment_history_order_idx
  on public.order_payment_history (order_id, created_at desc);

create index if not exists order_payment_history_created_at_idx
  on public.order_payment_history (created_at desc);

alter table public.order_payment_history enable row level security;

drop policy if exists "order_payment_history_select_admin" on public.order_payment_history;
create policy "order_payment_history_select_admin"
  on public.order_payment_history
  for select
  to authenticated
  using (
    public.is_admin()
  );

drop function if exists public.record_order_payment(bigint, numeric);
create or replace function public.record_order_payment(
  target_order_id bigint,
  payment_amount numeric,
  payment_note text default null
)
returns table (
  id bigint,
  client_id uuid,
  customer_name text,
  phone text,
  location text,
  product_id uuid,
  product_name text,
  quantity_kg numeric,
  price_per_kg numeric,
  total_price numeric,
  paid_amount numeric,
  remaining_balance numeric,
  is_credit boolean,
  status text,
  previous_status text,
  payment_amount_recorded numeric,
  became_completed boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  selected_order public.orders%rowtype;
  current_user_id uuid := auth.uid();
  previous_paid_amount_value numeric(10, 2);
  new_paid_amount numeric(10, 2);
  actual_payment_recorded_value numeric(10, 2);
  new_status text;
  remaining_balance_value numeric(10, 2);
  previous_status_value text;
begin
  if current_user_id is null then
    raise exception 'Not authenticated.';
  end if;

  if not public.is_admin() then
    raise exception 'Only admins can record payments.';
  end if;

  if payment_amount is null or payment_amount <= 0 then
    raise exception 'Payment amount must be greater than zero.';
  end if;

  select *
  into selected_order
  from public.orders
  where orders.id = target_order_id
  for update;

  if not found then
    raise exception 'Selected order was not found.';
  end if;

  if selected_order.status = 'Cancelled' then
    raise exception 'Cancelled orders cannot receive payments.';
  end if;


  if selected_order.status = 'Completed' then
    raise exception 'This order is already completed and cannot receive additional payments.';
  end if;

  if selected_order.paid_amount >= selected_order.total_price then
    raise exception 'This order is already fully paid.';
  end if;

  previous_status_value := selected_order.status;
  previous_paid_amount_value := selected_order.paid_amount;
  new_paid_amount := least(
    selected_order.total_price,
    previous_paid_amount_value + payment_amount
  );
  actual_payment_recorded_value := new_paid_amount - previous_paid_amount_value;
  remaining_balance_value := greatest(selected_order.total_price - new_paid_amount, 0);
  new_status := case
    when remaining_balance_value = 0 then 'Completed'
    when selected_order.status = 'Pending' then 'Received'
    else selected_order.status
  end;

  update public.orders as o
  set
    paid_amount = new_paid_amount,
    is_credit = new_paid_amount < o.total_price,
    status = new_status
  where o.id = selected_order.id
  returning * into selected_order;

  insert into public.order_payment_history (
    order_id,
    payment_amount,
    previous_paid_amount,
    new_paid_amount,
    previous_status,
    new_status,
    remaining_balance,
    recorded_by,
    note
  )
  values (
    selected_order.id,
    actual_payment_recorded_value,
    previous_paid_amount_value,
    selected_order.paid_amount,
    previous_status_value,
    selected_order.status,
    remaining_balance_value,
    current_user_id,
    nullif(trim(coalesce(payment_note, '')), '')
  );

  return query
  select
    selected_order.id,
    selected_order.client_id,
    selected_order.customer_name,
    selected_order.phone,
    selected_order.location,
    selected_order.product_id,
    selected_order.product_name,
    selected_order.quantity_kg,
    selected_order.price_per_kg,
    selected_order.total_price,
    selected_order.paid_amount,
    remaining_balance_value,
    selected_order.is_credit,
    selected_order.status,
    previous_status_value,
    actual_payment_recorded_value,
    selected_order.status = 'Completed' and previous_status_value <> 'Completed',
    selected_order.created_at;
end;
$$;

revoke execute on function public.record_order_payment(bigint, numeric, text) from anon;
grant execute on function public.record_order_payment(bigint, numeric, text)
to authenticated;
