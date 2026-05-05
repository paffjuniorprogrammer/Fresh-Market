-- Canonical base schema for a fresh Supabase database.
-- Run this file first on a new project.

create extension if not exists pgcrypto;

create table if not exists public.shops (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid,
  name text not null,
  description text not null default '',
  logo_url text not null default '',
  cover_image_url text not null default '',
  phone text not null default '',
  location text not null default '',
  address_line text not null default '',
  latitude double precision,
  longitude double precision,
  momo_pay_merchant_code text not null default '',
  bank_account text not null default '',
  delivery_base_fee numeric(10, 2) not null default 500,
  delivery_distance_threshold numeric(10, 2) not null default 4,
  delivery_extra_km_fee numeric(10, 2) not null default 200,
  delivery_order_threshold numeric(10, 2) not null default 20000,
  delivery_extra_order_percent numeric(10, 4) not null default 0.20,
  commission_percent numeric(5, 2) not null default 0 check (commission_percent >= 0 and commission_percent <= 100),
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now())
);

alter table public.shops
  add column if not exists address_line text not null default '',
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists delivery_base_fee numeric(10, 2) not null default 500,
  add column if not exists delivery_distance_threshold numeric(10, 2) not null default 4,
  add column if not exists delivery_extra_km_fee numeric(10, 2) not null default 200,
  add column if not exists delivery_order_threshold numeric(10, 2) not null default 20000,
  add column if not exists delivery_extra_order_percent numeric(10, 4) not null default 0.20;

insert into public.shops (
  id,
  name,
  description,
  logo_url,
  phone,
  location,
  momo_pay_merchant_code
)
values (
  '00000000-0000-0000-0000-000000000001',
  'Fresh Market',
  'Fresh groceries delivered fast',
  '',
  '',
  '',
  ''
)
on conflict (id) do nothing;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid references public.shops(id) on delete cascade,
  name text not null unique,
  image_url text not null default '',
  profit_percentage numeric(5, 2) not null default 0 check (profit_percentage >= 0),
  created_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid references public.shops(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  name text not null,
  description text not null,
  image_url text not null,
  unit text not null default 'kg' check (unit in ('kg', 'pc')),
  price numeric(10, 2) not null check (price > 0),
  purchase_price numeric(10, 2),
  selling_price numeric(10, 2),
  discount_price numeric(10, 2),
  discount_threshold_kg numeric(10, 2),
  quantity numeric(10, 2) not null default 0 check (quantity >= 0),
  is_available boolean not null default true,
  created_at timestamptz not null default timezone('utc'::text, now())
);

alter table public.products
  add column if not exists shop_id uuid references public.shops(id) on delete cascade,
  add column if not exists category_id uuid,
  add column if not exists unit text not null default 'kg',
  add column if not exists purchase_price numeric(10, 2),
  add column if not exists selling_price numeric(10, 2),
  add column if not exists discount_price numeric(10, 2),
  add column if not exists discount_threshold_kg numeric(10, 2);

update public.products
set unit = coalesce(nullif(trim(unit), ''), 'kg')
where unit is null or trim(unit) = '';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_unit_check'
  ) then
    alter table public.products
      add constraint products_unit_check
      check (unit in ('kg', 'pc'));
  end if;
end;
$$;

alter table public.categories
  add column if not exists shop_id uuid references public.shops(id) on delete cascade,
  add column if not exists image_url text not null default '';

alter table public.categories
  add column if not exists profit_percentage numeric(5, 2) not null default 0;

update public.categories
set shop_id = coalesce(shop_id, '00000000-0000-0000-0000-000000000001'),
    image_url = coalesce(image_url, ''),
    profit_percentage = coalesce(profit_percentage, 0)
where shop_id is null or profit_percentage is null or image_url is null;

update public.products
set shop_id = coalesce(shop_id, '00000000-0000-0000-0000-000000000001')
where shop_id is null;

alter table public.categories
  alter column profit_percentage set default 0;

alter table public.categories
  alter column profit_percentage set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_category_id_fkey'
  ) then
    alter table public.products
      add constraint products_category_id_fkey
      foreign key (category_id) references public.categories(id) on delete set null;
  end if;
end;
$$;

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text not null unique,
  location text not null,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.users (
  id uuid primary key,
  name text,
  phone text unique,
  email text,
  whatsapp text,
  location text,
  account_discount_percentage numeric(5, 2) not null default 0 check (account_discount_percentage >= 0 and account_discount_percentage <= 100),
  role text check (role in ('admin', 'shop_owner', 'client')),
  requested_role text not null default 'client',
  approval_status text not null default 'approved',
  requested_shop_name text,
  requested_shop_description text,
  approved_at timestamptz,
  rejection_reason text,
  created_at timestamp default now()
);

alter table public.users
  add column if not exists requested_role text not null default 'client',
  add column if not exists approval_status text not null default 'approved',
  add column if not exists requested_shop_name text,
  add column if not exists requested_shop_description text,
  add column if not exists approved_at timestamptz,
  add column if not exists rejection_reason text;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'users_role_check'
  ) then
    alter table public.users drop constraint users_role_check;
  end if;
  alter table public.users
    add constraint users_role_check
    check (role in ('admin', 'shop_owner', 'client'));
end;
$$;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'users_requested_role_check'
  ) then
    alter table public.users drop constraint users_requested_role_check;
  end if;
  alter table public.users
    add constraint users_requested_role_check
    check (requested_role in ('client', 'shop_owner'));
end;
$$;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'users_approval_status_check'
  ) then
    alter table public.users drop constraint users_approval_status_check;
  end if;
  alter table public.users
    add constraint users_approval_status_check
    check (approval_status in ('approved', 'pending', 'rejected'));
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'shops_owner_id_fkey'
  ) then
    alter table public.shops
      add constraint shops_owner_id_fkey
      foreign key (owner_id) references public.users(id) on delete set null;
  end if;
end;
$$;

update public.users
set
  name = nullif(trim(name), ''),
  phone = nullif(trim(phone), ''),
  email = nullif(trim(email), ''),
  requested_role = case
    when requested_role in ('client', 'shop_owner') then requested_role
    when role = 'shop_owner' then 'shop_owner'
    else 'client'
  end,
  approval_status = case
    when role = 'shop_owner' then 'approved'
    when approval_status in ('approved', 'pending', 'rejected') then approval_status
    else 'approved'
  end
where
  (name is not null and name <> trim(name))
  or (phone is not null and phone <> trim(phone))
  or (email is not null and email <> trim(email))
  or requested_role not in ('client', 'shop_owner')
  or approval_status not in ('approved', 'pending', 'rejected');

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
  requested_role_value text := case
    when lower(coalesce(new.raw_user_meta_data ->> 'requested_role', new.raw_user_meta_data ->> 'account_type', 'client')) = 'shop_owner'
    then 'shop_owner'
    else 'client'
  end;
  requested_shop_name_value text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'requested_shop_name', '')), '');
  requested_shop_description_value text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'requested_shop_description', '')), '');
  normalized_role text := case
    when lower(coalesce(new.email, new.raw_user_meta_data ->> 'email', '')) = 'paffpro01@gmail.com' then 'admin'
    when requested_role_value = 'shop_owner' then 'client'
    else 'client'
  end;
  approval_status_value text := case
    when lower(coalesce(new.email, new.raw_user_meta_data ->> 'email', '')) = 'paffpro01@gmail.com' then 'approved'
    when requested_role_value = 'shop_owner' then 'pending'
    else 'approved'
  end;
begin
  perform public.assert_user_identity_available(
    new.id,
    normalized_name,
    normalized_phone,
    normalized_email
  );

  insert into public.users (
    id,
    name,
    phone,
    email,
    location,
    role,
    requested_role,
    approval_status,
    requested_shop_name,
    requested_shop_description,
    approved_at,
    rejection_reason
  )
  values (
    new.id,
    normalized_name,
    normalized_phone,
    normalized_email,
    normalized_location,
    normalized_role,
    requested_role_value,
    approval_status_value,
    requested_shop_name_value,
    requested_shop_description_value,
    case when approval_status_value = 'approved' then timezone('utc'::text, now()) else null end,
    null
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
      end,
      requested_role = coalesce(excluded.requested_role, public.users.requested_role),
      approval_status = case
        when lower(coalesce(excluded.email, public.users.email, '')) = 'paffpro01@gmail.com' then 'approved'
        else coalesce(public.users.approval_status, excluded.approval_status)
      end,
      requested_shop_name = coalesce(excluded.requested_shop_name, public.users.requested_shop_name),
      requested_shop_description = coalesce(excluded.requested_shop_description, public.users.requested_shop_description),
      approved_at = case
        when lower(coalesce(excluded.email, public.users.email, '')) = 'paffpro01@gmail.com'
        then coalesce(public.users.approved_at, timezone('utc'::text, now()))
        else public.users.approved_at
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
  requested_role_value text;
  requested_shop_name_value text;
  requested_shop_description_value text;
  normalized_role text;
  approval_status_value text;
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
  requested_role_value := case
    when lower(coalesce(auth_user.raw_user_meta_data ->> 'requested_role', auth_user.raw_user_meta_data ->> 'account_type', 'client')) = 'shop_owner'
    then 'shop_owner'
    else 'client'
  end;
  requested_shop_name_value := nullif(trim(coalesce(auth_user.raw_user_meta_data ->> 'requested_shop_name', '')), '');
  requested_shop_description_value := nullif(trim(coalesce(auth_user.raw_user_meta_data ->> 'requested_shop_description', '')), '');
  normalized_role := case
    when lower(coalesce(auth_user.email, auth_user.raw_user_meta_data ->> 'email', '')) = 'paffpro01@gmail.com' then 'admin'
    when requested_role_value = 'shop_owner' then 'client'
    else 'client'
  end;
  approval_status_value := case
    when lower(coalesce(auth_user.email, auth_user.raw_user_meta_data ->> 'email', '')) = 'paffpro01@gmail.com' then 'approved'
    when requested_role_value = 'shop_owner' then 'pending'
    else 'approved'
  end;

  perform public.assert_user_identity_available(
    auth.uid(),
    normalized_name,
    normalized_phone,
    normalized_email
  );

  insert into public.users (
    id,
    name,
    phone,
    email,
    location,
    role,
    requested_role,
    approval_status,
    requested_shop_name,
    requested_shop_description,
    approved_at,
    rejection_reason
  )
  values (
    auth.uid(),
    normalized_name,
    normalized_phone,
    normalized_email,
    normalized_location,
    normalized_role,
    requested_role_value,
    approval_status_value,
    requested_shop_name_value,
    requested_shop_description_value,
    case when approval_status_value = 'approved' then timezone('utc'::text, now()) else null end,
    null
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
      end,
      requested_role = coalesce(excluded.requested_role, public.users.requested_role),
      approval_status = case
        when public.users.role = 'shop_owner' then 'approved'
        when lower(coalesce(excluded.email, public.users.email, '')) = 'paffpro01@gmail.com' then 'approved'
        else coalesce(public.users.approval_status, excluded.approval_status)
      end,
      requested_shop_name = coalesce(excluded.requested_shop_name, public.users.requested_shop_name),
      requested_shop_description = coalesce(excluded.requested_shop_description, public.users.requested_shop_description)
  returning * into ensured_user;

  return ensured_user;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

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

drop trigger if exists on_auth_user_email_updated on auth.users;
create trigger on_auth_user_email_updated
after update of email on auth.users
for each row
when (new.email is distinct from old.email)
execute function public.sync_auth_user_email();

create or replace function public.update_own_user_profile(
  display_name text,
  location_param text,
  whatsapp_param text default null,
  phone_param text default null
)
returns public.users
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_user public.users;
  normalized_name text := nullif(trim(coalesce(display_name, '')), '');
  normalized_phone text := nullif(trim(coalesce(phone_param, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Not authenticated.';
  end if;

  perform public.assert_user_identity_available(
    auth.uid(),
    normalized_name,
    normalized_phone,
    null
  );

  update public.users
  set
    name = normalized_name,
    location = nullif(trim(location_param), ''),
    whatsapp = nullif(trim(coalesce(whatsapp_param, '')), ''),
    phone = coalesce(normalized_phone, public.users.phone)
  where id = auth.uid()
  returning * into updated_user;

  if not found then
    raise exception 'User profile was not found.';
  end if;

  return updated_user;
end;
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users
    where id = auth.uid()
      and role = 'admin'
  );
$$;

create or replace function public.owns_shop(target_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin()
    or exists (
      select 1
      from public.shops
      where id = target_shop_id
        and owner_id = auth.uid()
    );
$$;

create or replace function public.approve_shop_owner(
  target_user_id uuid,
  shop_name_param text default null
)
returns public.users
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  selected_user public.users%rowtype;
  final_shop_name text;
begin
  if not public.is_admin() then
    raise exception 'Only admins can approve shop owners.';
  end if;

  select *
  into selected_user
  from public.users
  where id = target_user_id
  for update;

  if not found then
    raise exception 'Selected user was not found.';
  end if;

  if coalesce(selected_user.requested_role, 'client') <> 'shop_owner'
     or coalesce(selected_user.approval_status, 'approved') <> 'pending' then
    raise exception 'This user is not waiting for shop approval.';
  end if;

  final_shop_name := coalesce(
    nullif(trim(coalesce(shop_name_param, '')), ''),
    nullif(trim(coalesce(selected_user.requested_shop_name, '')), ''),
    nullif(trim(coalesce(selected_user.name, '')), ''),
    'Partner Shop'
  );

  update public.users
  set
    role = 'shop_owner',
    requested_role = 'shop_owner',
    approval_status = 'approved',
    approved_at = timezone('utc'::text, now()),
    rejection_reason = null
  where id = selected_user.id
  returning * into selected_user;

  insert into public.shops (
    owner_id,
    name,
    description,
    phone,
    location
  )
  values (
    selected_user.id,
    final_shop_name,
    coalesce(selected_user.requested_shop_description, ''),
    coalesce(selected_user.phone, ''),
    coalesce(selected_user.location, '')
  )
  on conflict do nothing;

  return selected_user;
end;
$$;

grant execute on function public.approve_shop_owner(uuid, text)
to authenticated;

create or replace function public.reject_shop_owner(
  target_user_id uuid,
  reason_param text default null
)
returns public.users
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  selected_user public.users%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only admins can reject shop owners.';
  end if;

  update public.users
  set
    role = 'client',
    requested_role = 'shop_owner',
    approval_status = 'rejected',
    rejection_reason = nullif(trim(coalesce(reason_param, '')), '')
  where id = target_user_id
  returning * into selected_user;

  if not found then
    raise exception 'Selected user was not found.';
  end if;

  return selected_user;
end;
$$;

grant execute on function public.reject_shop_owner(uuid, text)
to authenticated;

create table if not exists public.locations (
  user_id uuid primary key references public.users(id) on delete cascade,
  customer_name text not null default '',
  phone text,
  location_label text,
  latitude double precision not null,
  longitude double precision not null,
  updated_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.admin_tokens (
  fcm_token text primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  platform text not null default 'unknown',
  updated_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.client_tokens (
  fcm_token text primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  platform text not null default 'unknown',
  updated_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.business_profile (
  id integer primary key default 1,
  business_name text not null default 'Fresh Market',
  email text not null default '',
  phone text not null default '',
  location text not null default '',
  address_line text not null default '',
  latitude double precision,
  longitude double precision,
  momo_pay_merchant_code text not null default '',
  delivery_base_fee numeric(10, 2) not null default 500,
  delivery_distance_threshold numeric(10, 2) not null default 4,
  delivery_extra_km_fee numeric(10, 2) not null default 200,
  delivery_order_threshold numeric(10, 2) not null default 20000,
  delivery_extra_order_percent numeric(10, 4) not null default 0.20,
  updated_at timestamptz not null default timezone('utc'::text, now())
);

alter table public.business_profile
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists momo_pay_merchant_code text default '',
  add column if not exists delivery_base_fee numeric(10, 2) not null default 500,
  add column if not exists delivery_distance_threshold numeric(10, 2) not null default 4,
  add column if not exists delivery_extra_km_fee numeric(10, 2) not null default 200,
  add column if not exists delivery_order_threshold numeric(10, 2) not null default 20000,
  add column if not exists delivery_extra_order_percent numeric(10, 4) not null default 0.20;

insert into public.business_profile (
  id,
  business_name,
  latitude,
  longitude
)
values (
  1,
  'Fresh Market',
  -1.4995,
  29.6348
)
on conflict (id) do nothing;

create table if not exists public.price_history (
  id bigint generated by default as identity primary key,
  entity_type text not null check (entity_type in ('product', 'category')),
  entity_id uuid not null,
  field_name text not null,
  old_value numeric(10, 2),
  new_value numeric(10, 2) not null,
  changed_by uuid references public.users(id) on delete set null,
  note text,
  created_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.orders (
  id bigint generated by default as identity primary key,
  shop_id uuid references public.shops(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  client_id uuid references public.users(id) on delete set null,
  customer_name text not null,
  phone text not null,
  location text not null,
  delivery_location_label text,
  delivery_latitude double precision,
  delivery_longitude double precision,
  delivery_position_updated_at timestamptz,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  quantity_kg numeric(10, 2) not null check (quantity_kg > 0),
  price_per_kg numeric(10, 2) not null check (price_per_kg > 0),
  total_price numeric(10, 2) not null check (total_price >= 0),
  delivery_fee numeric(10, 2) not null default 0 check (delivery_fee >= 0),
  paid_amount numeric(10, 2) not null default 0 check (paid_amount >= 0),
  is_credit boolean not null default false,
  payment_method text not null default 'Cash',
  cancel_reason text,
  status text not null default 'Pending'
    check (status in ('Pending', 'Received', 'Completed', 'Cancelled')),
  created_at timestamptz not null default timezone('utc'::text, now())
);

alter table public.orders
  add column if not exists shop_id uuid references public.shops(id) on delete restrict,
  add column if not exists delivery_location_label text,
  add column if not exists delivery_latitude double precision,
  add column if not exists delivery_longitude double precision,
  add column if not exists delivery_position_updated_at timestamptz,
  add column if not exists delivery_fee numeric(10, 2) not null default 0,
  add column if not exists payment_method text not null default 'Cash',
  add column if not exists cancel_reason text;

update public.orders
set
  shop_id = coalesce(shop_id, '00000000-0000-0000-0000-000000000001'),
  delivery_fee = coalesce(delivery_fee, 0),
  payment_method = coalesce(nullif(trim(payment_method), ''), 'Cash')
where shop_id is null
   or delivery_fee is null
   or payment_method is null
   or trim(payment_method) = '';

alter table public.orders
  alter column delivery_fee set default 0;

alter table public.orders
  alter column delivery_fee set not null;

alter table public.orders
  alter column payment_method set default 'Cash';

alter table public.orders
  alter column payment_method set not null;

create table if not exists public.order_items (
  id bigint generated by default as identity primary key,
  order_id bigint not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  quantity_kg numeric(10, 2) not null check (quantity_kg > 0),
  price_per_kg numeric(10, 2) not null check (price_per_kg > 0),
  unit text not null default 'kg' check (unit in ('kg', 'pc')),
  created_at timestamptz not null default timezone('utc'::text, now())
);

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

alter table public.order_items
  add column if not exists unit text not null default 'kg',
  add column if not exists created_at timestamptz not null default timezone('utc'::text, now());

update public.order_items
set unit = coalesce(nullif(trim(unit), ''), 'kg')
where unit is null or trim(unit) = '';

update public.order_items
set created_at = coalesce(created_at, timezone('utc'::text, now()))
where created_at is null;

alter table public.order_items
  alter column unit set default 'kg';

alter table public.order_items
  alter column unit set not null;

alter table public.order_items
  alter column created_at set default timezone('utc'::text, now());

alter table public.order_items
  alter column created_at set not null;

create or replace function public.sync_order_item_from_legacy_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.product_id is null
     or new.quantity_kg is null
     or new.price_per_kg is null
     or exists (
       select 1
       from public.order_items
       where order_items.order_id = new.id
     ) then
    return new;
  end if;

  insert into public.order_items (
    order_id,
    product_id,
    product_name,
    quantity_kg,
    price_per_kg,
    unit,
    created_at
  )
  select
    new.id,
    new.product_id,
    coalesce(nullif(trim(new.product_name), ''), products.name),
    new.quantity_kg,
    new.price_per_kg,
    coalesce(nullif(trim(products.unit), ''), 'kg'),
    coalesce(new.created_at, timezone('utc'::text, now()))
  from public.products
  where products.id = new.product_id;

  return new;
end;
$$;

drop trigger if exists sync_order_item_from_legacy_order on public.orders;
create trigger sync_order_item_from_legacy_order
after insert on public.orders
for each row execute function public.sync_order_item_from_legacy_order();

insert into public.order_items (
  order_id,
  product_id,
  product_name,
  quantity_kg,
  price_per_kg,
  unit,
  created_at
)
select
  orders.id,
  orders.product_id,
  coalesce(nullif(trim(orders.product_name), ''), products.name),
  orders.quantity_kg,
  orders.price_per_kg,
  coalesce(nullif(trim(products.unit), ''), 'kg'),
  coalesce(orders.created_at, timezone('utc'::text, now()))
from public.orders
join public.products on products.id = orders.product_id
where not exists (
  select 1
  from public.order_items
  where order_items.order_id = orders.id
);


create index if not exists categories_name_idx
  on public.categories (name);

create index if not exists products_created_at_idx
  on public.products (created_at desc);

create index if not exists products_category_id_idx
  on public.products (category_id);

create index if not exists products_shop_id_idx
  on public.products (shop_id);

create index if not exists orders_created_at_idx
  on public.orders (created_at desc);

create index if not exists orders_shop_id_idx
  on public.orders (shop_id);

create index if not exists orders_phone_idx
  on public.orders (phone);

create index if not exists order_items_order_id_idx
  on public.order_items (order_id);

create index if not exists order_items_product_id_idx
  on public.order_items (product_id);

create index if not exists locations_updated_at_idx
  on public.locations (updated_at desc);

create index if not exists admin_tokens_user_id_idx
  on public.admin_tokens (user_id);

create index if not exists client_tokens_user_id_idx
  on public.client_tokens (user_id);

create index if not exists business_profile_updated_at_idx
  on public.business_profile (updated_at desc);

create index if not exists price_history_entity_idx
  on public.price_history (entity_type, entity_id, created_at desc);

create index if not exists price_history_created_at_idx
  on public.price_history (created_at desc);

create index if not exists order_payment_history_order_idx
  on public.order_payment_history (order_id, created_at desc);

create index if not exists order_payment_history_created_at_idx
  on public.order_payment_history (created_at desc);

alter table public.shops enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_payment_history enable row level security;

drop policy if exists "shops_select_public" on public.shops;
create policy "shops_select_public"
  on public.shops
  for select
  to anon, authenticated
  using (is_active or public.is_admin() or owner_id = auth.uid());

drop policy if exists "shops_insert_admin" on public.shops;
create policy "shops_insert_admin"
  on public.shops
  for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists "shops_update_owner_or_admin" on public.shops;
create policy "shops_update_owner_or_admin"
  on public.shops
  for update
  to authenticated
  using (public.is_admin() or owner_id = auth.uid())
  with check (public.is_admin() or owner_id = auth.uid());

drop policy if exists "shops_delete_admin" on public.shops;
create policy "shops_delete_admin"
  on public.shops
  for delete
  to authenticated
  using (public.is_admin());

drop policy if exists "categories_select_public" on public.categories;
create policy "categories_select_public"
  on public.categories
  for select
  to anon, authenticated
  using (true);

drop policy if exists "categories_insert_public" on public.categories;
create policy "categories_insert_public"
  on public.categories
  for insert
  to authenticated
  with check (public.is_admin() or public.owns_shop(shop_id));

drop policy if exists "categories_update_public" on public.categories;
create policy "categories_update_public"
  on public.categories
  for update
  to authenticated
  using (public.is_admin() or public.owns_shop(shop_id))
  with check (public.is_admin() or public.owns_shop(shop_id));

drop policy if exists "categories_delete_public" on public.categories;
create policy "categories_delete_public"
  on public.categories
  for delete
  to authenticated
  using (public.is_admin() or public.owns_shop(shop_id));

drop policy if exists "products_select_public" on public.products;
create policy "products_select_public"
  on public.products
  for select
  to anon, authenticated
  using (true);

drop policy if exists "products_insert_public" on public.products;
create policy "products_insert_public"
  on public.products
  for insert
  to authenticated
  with check (public.is_admin() or public.owns_shop(shop_id));

drop policy if exists "products_update_public" on public.products;
create policy "products_update_public"
  on public.products
  for update
  to authenticated
  using (public.is_admin() or public.owns_shop(shop_id))
  with check (public.is_admin() or public.owns_shop(shop_id));

drop policy if exists "products_delete_public" on public.products;
create policy "products_delete_public"
  on public.products
  for delete
  to authenticated
  using (public.is_admin() or public.owns_shop(shop_id));

alter table public.users enable row level security;
alter table public.locations enable row level security;
alter table public.admin_tokens enable row level security;
alter table public.client_tokens enable row level security;
alter table public.business_profile enable row level security;
alter table public.price_history enable row level security;

drop policy if exists "users_admin_all" on public.users;
create policy "users_admin_all"
  on public.users
  for all
  using (
    public.is_admin()
  );

drop policy if exists "users_client_update" on public.users;
-- client profile updates are handled through public.update_own_user_profile()

drop policy if exists "users_client_select" on public.users;
create policy "users_client_select"
  on public.users
  for select
  using (auth.uid() = id);

drop policy if exists "users_client_insert" on public.users;
-- user rows are created by the auth.users trigger above

drop policy if exists "locations_select_authenticated" on public.locations;
create policy "locations_select_authenticated"
  on public.locations
  for select
  to authenticated
  using (true);

drop policy if exists "locations_insert_own" on public.locations;
create policy "locations_insert_own"
  on public.locations
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "locations_update_own" on public.locations;
create policy "locations_update_own"
  on public.locations
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "admin_tokens_select_authenticated" on public.admin_tokens;
create policy "admin_tokens_select_authenticated"
  on public.admin_tokens
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "admin_tokens_insert_own" on public.admin_tokens;
create policy "admin_tokens_insert_own"
  on public.admin_tokens
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "admin_tokens_update_own" on public.admin_tokens;
create policy "admin_tokens_update_own"
  on public.admin_tokens
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "admin_tokens_delete_own" on public.admin_tokens;
create policy "admin_tokens_delete_own"
  on public.admin_tokens
  for delete
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "client_tokens_select_authenticated" on public.client_tokens;
create policy "client_tokens_select_authenticated"
  on public.client_tokens
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "client_tokens_insert_own" on public.client_tokens;
create policy "client_tokens_insert_own"
  on public.client_tokens
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "client_tokens_update_own" on public.client_tokens;
create policy "client_tokens_update_own"
  on public.client_tokens
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "client_tokens_delete_own" on public.client_tokens;
create policy "client_tokens_delete_own"
  on public.client_tokens
  for delete
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "business_profile_select_authenticated" on public.business_profile;
create policy "business_profile_select_authenticated"
  on public.business_profile
  for select
  to authenticated
  using (true);

drop policy if exists "business_profile_modify_admin" on public.business_profile;
create policy "business_profile_modify_admin"
  on public.business_profile
  for all
  using (
    public.is_admin()
  )
  with check (
    public.is_admin()
  );

drop policy if exists "price_history_select_admin" on public.price_history;
create policy "price_history_select_admin"
  on public.price_history
  for select
  to authenticated
  using (
    public.is_admin()
  );

drop policy if exists "price_history_insert_admin" on public.price_history;
create policy "price_history_insert_admin"
  on public.price_history
  for insert
  to authenticated
  with check (
    public.is_admin()
  );

drop policy if exists "order_payment_history_select_admin" on public.order_payment_history;
create policy "order_payment_history_select_admin"
  on public.order_payment_history
  for select
  to authenticated
  using (
    public.is_admin()
  );

drop policy if exists "customers_select_public" on public.customers;
create policy "customers_select_public"
  on public.customers
  for select
  to authenticated
  using (public.is_admin());

drop policy if exists "customers_insert_public" on public.customers;
create policy "customers_insert_public"
  on public.customers
  for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists "customers_update_public" on public.customers;
create policy "customers_update_public"
  on public.customers
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "orders_select_public" on public.orders;
create policy "orders_select_public"
  on public.orders
  for select
  to authenticated
  using (public.is_admin() or auth.uid() = client_id or public.owns_shop(shop_id));

drop policy if exists "orders_update_public" on public.orders;
create policy "orders_update_public"
  on public.orders
  for update
  to authenticated
  using (public.is_admin() or public.owns_shop(shop_id))
  with check (public.is_admin() or public.owns_shop(shop_id));

drop policy if exists "orders_delete_public" on public.orders;
create policy "orders_delete_public"
  on public.orders
  for delete
  to authenticated
  using (public.is_admin() or public.owns_shop(shop_id));

drop policy if exists "order_items_select_accessible" on public.order_items;
create policy "order_items_select_accessible"
  on public.order_items
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.orders
      where orders.id = order_items.order_id
        and (
          public.is_admin()
          or auth.uid() = orders.client_id
          or public.owns_shop(orders.shop_id)
        )
    )
  );

drop policy if exists "order_items_modify_admin" on public.order_items;
create policy "order_items_modify_admin"
  on public.order_items
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.orders
      where orders.id = order_items.order_id
        and (public.is_admin() or public.owns_shop(orders.shop_id))
    )
  )
  with check (
    exists (
      select 1
      from public.orders
      where orders.id = order_items.order_id
        and (public.is_admin() or public.owns_shop(orders.shop_id))
    )
  );

drop policy if exists "Client can see own data" on public.orders;
create policy "Client can see own data"
  on public.orders
  for select
  using (auth.uid() = client_id);

-- Canonical schema only. Seed/demo data lives in supabase/seed.sql.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'products',
  'products',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "product_images_select_public" on storage.objects;
create policy "product_images_select_public"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'products'
    and (
      public.is_admin()
      or exists (
        select 1
        from public.users
        where id = auth.uid()
          and role = 'shop_owner'
      )
    )
  );

drop policy if exists "product_images_insert_public" on storage.objects;
create policy "product_images_insert_public"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'products'
    and (
      public.is_admin()
      or exists (
        select 1
        from public.users
        where id = auth.uid()
          and role = 'shop_owner'
      )
    )
  );

drop policy if exists "product_images_update_public" on storage.objects;
create policy "product_images_update_public"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'products'
    and (
      public.is_admin()
      or exists (
        select 1
        from public.users
        where id = auth.uid()
          and role = 'shop_owner'
      )
    )
  )
  with check (
    bucket_id = 'products'
    and (
      public.is_admin()
      or exists (
        select 1
        from public.users
        where id = auth.uid()
          and role = 'shop_owner'
      )
    )
  );

drop policy if exists "product_images_delete_public" on storage.objects;
create policy "product_images_delete_public"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'products'
    and (
      public.is_admin()
      or exists (
        select 1
        from public.users
        where id = auth.uid()
          and role = 'shop_owner'
      )
    )
  );

drop function if exists public.place_order(
  text,
  text,
  text,
  uuid,
  numeric,
  numeric,
  boolean,
  uuid
);

create or replace function public.place_order(
  order_customer_name text,
  order_phone text,
  order_location text,
  order_product_id uuid,
  order_quantity_kg numeric,
  order_paid_amount numeric default 0,
  order_is_credit boolean default false,
  order_client_id uuid default null
)
returns table (
  id bigint,
  customer_name text,
  phone text,
  location text,
  product_id uuid,
  product_name text,
  quantity_kg numeric,
  price_per_kg numeric,
  total_price numeric,
  paid_amount numeric,
  is_credit boolean,
  status text,
  remaining_quantity numeric,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_product public.products%rowtype;
  selected_customer_id uuid;
  selected_client_discount numeric(5, 2) := 0;
  applied_price numeric(10, 2);
  calculated_total numeric(10, 2);
  discount_amount numeric(10, 2);
  discounted_total numeric(10, 2);
  normalized_paid numeric(10, 2);
  remaining_stock numeric(10, 2);
begin
  if coalesce(trim(order_customer_name), '') = '' then
    raise exception 'Customer name is required.';
  end if;

  if coalesce(trim(order_phone), '') = '' then
    raise exception 'Phone number is required.';
  end if;

  if coalesce(trim(order_location), '') = '' then
    raise exception 'Delivery location is required.';
  end if;

  if order_quantity_kg is null or order_quantity_kg <= 0 then
    raise exception 'Order quantity must be greater than zero.';
  end if;

  select *
  into selected_product
  from public.products
  where products.id = order_product_id
  for update;

  if not found then
    raise exception 'Selected product was not found.';
  end if;

  if not selected_product.is_available then
    raise exception 'Selected product is currently unavailable.';
  end if;

  if selected_product.quantity < order_quantity_kg then
    raise exception 'Only % Kg are available for %.',
      selected_product.quantity,
      selected_product.name;
  end if;

  if order_client_id is not null then
    select greatest(coalesce(account_discount_percentage, 0), 0)
    into selected_client_discount
    from public.users
    where id = order_client_id
      and role = 'client';
  end if;

  applied_price := case
    when selected_product.discount_price is not null
      and selected_product.discount_threshold_kg is not null
      and order_quantity_kg >= selected_product.discount_threshold_kg
    then selected_product.discount_price
    else selected_product.price
  end;

  calculated_total := applied_price * order_quantity_kg;
  discount_amount := round(calculated_total * selected_client_discount / 100, 2);
  discounted_total := greatest(calculated_total - discount_amount, 0);
  normalized_paid := case
    when order_is_credit then greatest(coalesce(order_paid_amount, 0), 0)
    else discounted_total
  end;

  if normalized_paid > discounted_total then
    raise exception 'Paid amount cannot exceed the total order price.';
  end if;

  insert into public.customers (full_name, phone, location)
  values (
    trim(order_customer_name),
    trim(order_phone),
    trim(order_location)
  )
  on conflict (phone) do update
    set
      full_name = excluded.full_name,
      location = excluded.location,
      updated_at = timezone('utc'::text, now())
  returning customers.id into selected_customer_id;

  update public.products
  set
    quantity = quantity - order_quantity_kg,
    is_available = case
      when quantity - order_quantity_kg > 0 then is_available
      else false
    end
  where products.id = selected_product.id
  returning products.quantity into remaining_stock;

  return query
  insert into public.orders (
    shop_id,
    customer_id,
    client_id,
    customer_name,
    phone,
    location,
    product_id,
    product_name,
    quantity_kg,
    price_per_kg,
    total_price,
    paid_amount,
    is_credit,
    status
  )
  values (
    coalesce(selected_product.shop_id, '00000000-0000-0000-0000-000000000001'),
    selected_customer_id,
    order_client_id,
    trim(order_customer_name),
    trim(order_phone),
    trim(order_location),
    selected_product.id,
    selected_product.name,
    order_quantity_kg,
    applied_price,
    discounted_total,
    normalized_paid,
    order_is_credit,
    'Pending'
  )
  returning
    orders.id,
    orders.customer_name,
    orders.phone,
    orders.location,
    orders.product_id,
    orders.product_name,
    orders.quantity_kg,
    orders.price_per_kg,
    orders.total_price,
    orders.paid_amount,
    orders.is_credit,
    orders.status,
    remaining_stock,
    orders.created_at;
end;
$$;

grant execute on function public.place_order(
  text,
  text,
  text,
  uuid,
  numeric,
  numeric,
  boolean,
  uuid
) to anon, authenticated;

drop function if exists public.place_grouped_order(
  text,
  text,
  text,
  jsonb,
  boolean,
  numeric,
  numeric,
  text,
  text,
  double precision,
  double precision,
  uuid
);

create or replace function public.place_grouped_order(
  customer_name_param text,
  phone_param text,
  location_param text,
  items_json jsonb,
  is_credit_param boolean default false,
  paid_amount_param numeric default 0,
  delivery_fee_param numeric default 0,
  payment_method_param text default 'Cash',
  delivery_location_label_param text default null,
  delivery_latitude_param double precision default null,
  delivery_longitude_param double precision default null,
  client_id_param uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_client_id uuid := coalesce(client_id_param, auth.uid());
  selected_customer_id uuid;
  selected_client_discount numeric(5, 2) := 0;
  normalized_delivery_fee numeric(10, 2) := greatest(coalesce(delivery_fee_param, 0), 0);
  normalized_payment_method text := coalesce(nullif(trim(coalesce(payment_method_param, '')), ''), 'Cash');
  normalized_delivery_location_label text := nullif(trim(coalesce(delivery_location_label_param, '')), '');
  normalized_paid numeric(10, 2);
  items_subtotal numeric(10, 2) := 0;
  total_order_amount numeric(10, 2);
  inserted_order_id bigint;
  first_product_id uuid;
  first_product_name text;
  first_quantity_kg numeric(10, 2);
  first_price_per_kg numeric(10, 2);
  selected_shop_id uuid;
  validated_items jsonb := '[]'::jsonb;
  current_item record;
  line_base_price numeric(10, 2);
  line_effective_price numeric(10, 2);
  line_total numeric(10, 2);
  item_rank integer := 0;
begin
  if coalesce(trim(customer_name_param), '') = '' then
    raise exception 'Customer name is required.';
  end if;

  if coalesce(trim(phone_param), '') = '' then
    raise exception 'Phone number is required.';
  end if;

  if coalesce(trim(location_param), '') = '' then
    raise exception 'Delivery location is required.';
  end if;

  if items_json is null
     or jsonb_typeof(items_json) <> 'array'
     or jsonb_array_length(items_json) = 0 then
    raise exception 'At least one order item is required.';
  end if;

  if auth.uid() is not null
     and client_id_param is not null
     and client_id_param <> auth.uid() then
    raise exception 'You can only place orders for your own account.';
  end if;

  if normalized_client_id is not null then
    select greatest(coalesce(account_discount_percentage, 0), 0)
    into selected_client_discount
    from public.users
    where id = normalized_client_id
      and role = 'client';
  end if;

  for current_item in
    with normalized_items as (
      select
        (value ->> 'product_id')::uuid as product_id,
        sum(coalesce((value ->> 'quantity_kg')::numeric, 0))::numeric(10, 2) as quantity_kg
      from jsonb_array_elements(items_json) as value
      group by 1
    )
    select
      normalized_items.product_id,
      normalized_items.quantity_kg,
      products.name as product_name,
      coalesce(products.shop_id, '00000000-0000-0000-0000-000000000001') as shop_id,
      coalesce(nullif(trim(products.unit), ''), 'kg') as unit,
      products.price,
      products.discount_price,
      products.discount_threshold_kg,
      products.is_available,
      products.quantity as available_quantity
    from normalized_items
    join public.products on products.id = normalized_items.product_id
    order by products.name nulls last, normalized_items.product_id
    for update of products
  loop
    if current_item.product_id is null then
      raise exception 'Each order item must include a valid product.';
    end if;

    if current_item.quantity_kg is null or current_item.quantity_kg <= 0 then
      raise exception 'Each order item must have quantity greater than zero.';
    end if;

    if current_item.product_name is null then
      raise exception 'Selected product was not found.';
    end if;

    if not coalesce(current_item.is_available, false) then
      raise exception 'Selected product % is currently unavailable.', current_item.product_name;
    end if;

    if selected_shop_id is null then
      selected_shop_id := current_item.shop_id;
    elsif selected_shop_id <> current_item.shop_id then
      raise exception 'Please order from one shop at a time.';
    end if;

    if coalesce(current_item.available_quantity, 0) < current_item.quantity_kg then
      raise exception 'Only % Kg are available for %.',
        current_item.available_quantity,
        current_item.product_name;
    end if;

    line_base_price := case
      when current_item.discount_price is not null
        and current_item.discount_threshold_kg is not null
        and current_item.quantity_kg >= current_item.discount_threshold_kg
      then current_item.discount_price
      else current_item.price
    end;

    line_effective_price := case
      when selected_client_discount > 0
      then round(line_base_price * (100 - selected_client_discount) / 100, 2)
      else line_base_price
    end;

    line_total := round(current_item.quantity_kg * line_effective_price, 2);
    items_subtotal := items_subtotal + line_total;
    item_rank := item_rank + 1;

    if item_rank = 1 then
      first_product_id := current_item.product_id;
      first_product_name := current_item.product_name;
      first_quantity_kg := current_item.quantity_kg;
      first_price_per_kg := line_effective_price;
    end if;

    validated_items := validated_items || jsonb_build_array(
      jsonb_build_object(
        'item_rank', item_rank,
        'product_id', current_item.product_id,
        'product_name', current_item.product_name,
        'quantity_kg', current_item.quantity_kg,
        'price_per_kg', line_effective_price,
        'unit', current_item.unit
      )
    );
  end loop;

  if item_rank = 0 then
    raise exception 'At least one valid order item is required.';
  end if;

  normalized_paid := greatest(coalesce(paid_amount_param, 0), 0);
  total_order_amount := round(items_subtotal + normalized_delivery_fee, 2);

  if normalized_paid > total_order_amount then
    raise exception 'Paid amount cannot exceed the total order price.';
  end if;

  insert into public.customers (full_name, phone, location)
  values (
    trim(customer_name_param),
    trim(phone_param),
    trim(location_param)
  )
  on conflict (phone) do update
    set
      full_name = excluded.full_name,
      location = excluded.location,
      updated_at = timezone('utc'::text, now())
  returning customers.id into selected_customer_id;

  insert into public.orders (
    shop_id,
    customer_id,
    client_id,
    customer_name,
    phone,
    location,
    delivery_location_label,
    delivery_latitude,
    delivery_longitude,
    delivery_position_updated_at,
    product_id,
    product_name,
    quantity_kg,
    price_per_kg,
    total_price,
    delivery_fee,
    paid_amount,
    is_credit,
    payment_method,
    status
  )
  values (
    selected_shop_id,
    selected_customer_id,
    normalized_client_id,
    trim(customer_name_param),
    trim(phone_param),
    trim(location_param),
    normalized_delivery_location_label,
    delivery_latitude_param,
    delivery_longitude_param,
    case
      when delivery_latitude_param is not null and delivery_longitude_param is not null
      then timezone('utc'::text, now())
      else null
    end,
    first_product_id,
    first_product_name,
    first_quantity_kg,
    first_price_per_kg,
    total_order_amount,
    normalized_delivery_fee,
    normalized_paid,
    coalesce(is_credit_param, false),
    normalized_payment_method,
    'Pending'
  )
  returning id into inserted_order_id;

  for current_item in
    select *
    from jsonb_to_recordset(validated_items) as items(
      item_rank integer,
      product_id uuid,
      product_name text,
      quantity_kg numeric(10, 2),
      price_per_kg numeric(10, 2),
      unit text
    )
  loop
    update public.products
    set
      quantity = quantity - current_item.quantity_kg,
      is_available = case
        when quantity - current_item.quantity_kg > 0 then is_available
        else false
      end
    where products.id = current_item.product_id;

    if current_item.item_rank > 1 then
      insert into public.order_items (
        order_id,
        product_id,
        product_name,
        quantity_kg,
        price_per_kg,
        unit
      )
      values (
        inserted_order_id,
        current_item.product_id,
        current_item.product_name,
        current_item.quantity_kg,
        current_item.price_per_kg,
        current_item.unit
      );
    end if;
  end loop;

  return inserted_order_id;
end;
$$;

grant execute on function public.place_grouped_order(
  text,
  text,
  text,
  jsonb,
  boolean,
  numeric,
  numeric,
  text,
  text,
  double precision,
  double precision,
  uuid
) to authenticated;

create or replace function public.record_order_payment(
  target_order_id bigint,
  payment_amount numeric,
  payment_note text default null,
  admin_user_id uuid default null
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
  current_user_id uuid := coalesce(admin_user_id, auth.uid());
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

  if not exists (
    select 1
    from public.users
    where id = current_user_id
      and role = 'admin'
  ) and not exists (
    select 1
    from public.shops
    where id = selected_order.shop_id
      and owner_id = current_user_id
  ) then
    raise exception 'Only admins or this shop owner can record payments.';
  end if;

  if selected_order.status = 'Cancelled' then
    raise exception 'Cancelled orders cannot receive payments.';
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

drop function if exists public.record_order_payment(bigint, numeric);
revoke execute on function public.record_order_payment(bigint, numeric, text) from anon;
grant execute on function public.record_order_payment(bigint, numeric, text)
to authenticated;

drop function if exists public.cancel_order(bigint);
create or replace function public.cancel_order(
  target_order_id bigint,
  cancel_reason_param text default null
)
returns public.orders
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  selected_order public.orders%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated.';
  end if;

  select *
  into selected_order
  from public.orders
  where orders.id = target_order_id
  for update;

  if not found then
    raise exception 'Selected order was not found.';
  end if;

  if selected_order.client_id is distinct from auth.uid() then
    raise exception 'You can only cancel your own orders.';
  end if;

  if selected_order.status = 'Cancelled' then
    raise exception 'This order is already cancelled.';
  end if;

  if selected_order.status = 'Completed' then
    raise exception 'Completed orders cannot be cancelled.';
  end if;

  if selected_order.paid_amount > 0 then
    raise exception 'Paid orders cannot be cancelled online. Contact support.';
  end if;

  if coalesce(trim(cancel_reason_param), '') = '' then
    raise exception 'Cancel reason is required.';
  end if;

  update public.orders
  set
    status = 'Cancelled',
    cancel_reason = trim(cancel_reason_param)
  where id = selected_order.id
  returning * into selected_order;

  return selected_order;
end;
$$;

revoke execute on function public.cancel_order(bigint, text) from anon;
grant execute on function public.cancel_order(bigint, text)
to authenticated;

drop view if exists public.outstanding_debts cascade;
create or replace view public.outstanding_debts as
with order_lines as (
  select
    orders.id as order_id,
    orders.customer_name,
    orders.phone,
    orders.location,
    order_items.product_id,
    order_items.product_name,
    order_items.quantity_kg,
    (order_items.quantity_kg * order_items.price_per_kg)::numeric(10, 2) as line_total,
    sum(order_items.quantity_kg * order_items.price_per_kg)
      over (partition by orders.id)::numeric(10, 2) as items_total,
    least(
      coalesce(orders.paid_amount, 0),
      greatest(coalesce(orders.total_price, 0) - coalesce(orders.delivery_fee, 0), 0)
    )::numeric(10, 2) as paid_against_items
  from public.orders
  join public.order_items
    on order_items.order_id = orders.id
  where orders.status <> 'Cancelled'
),
allocated_lines as (
  select
    customer_name,
    phone,
    location,
    product_id,
    product_name,
    quantity_kg,
    line_total,
    case
      when items_total <= 0 then 0::numeric(10, 2)
      else round(paid_against_items * line_total / items_total, 2)
    end as line_paid
  from order_lines
)
select
  customer_name,
  phone,
  location,
  product_id,
  product_name,
  sum(quantity_kg)::numeric(10, 2) as quantity_kg,
  sum(line_total)::numeric(10, 2) as total_amount,
  sum(line_paid)::numeric(10, 2) as paid_amount,
  sum(line_total - line_paid)::numeric(10, 2) as balance
from allocated_lines
group by
  customer_name,
  phone,
  location,
  product_id,
  product_name
having sum(line_total - line_paid) > 0;

drop view if exists public.client_summaries cascade;
create or replace view public.client_summaries as
select
  u.id as client_id,
  coalesce(nullif(trim(u.name), ''), 'Client') as client_name,
  coalesce(u.phone, '') as phone,
  coalesce(u.location, '') as location,
  coalesce(u.account_discount_percentage, 0)::numeric(5, 2) as account_discount_percentage,
  count(o.id)::int as orders_count,
  coalesce(sum(o.total_price), 0)::numeric(10, 2) as total_spent,
  coalesce(sum(o.paid_amount), 0)::numeric(10, 2) as total_paid,
  coalesce(sum(o.total_price - o.paid_amount), 0)::numeric(10, 2) as total_debt,
  max(o.created_at) as last_order_at
from public.users u
left join public.orders o
  on (
    o.client_id = u.id
    or (o.client_id is null and o.phone = u.phone)
  )
  and o.status <> 'Cancelled'
where u.role = 'client'
group by u.id, u.name, u.phone, u.location, u.account_discount_percentage;

grant select on public.outstanding_debts to authenticated;
grant select on public.client_summaries to authenticated;
