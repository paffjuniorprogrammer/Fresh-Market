alter table public.users
  add column if not exists requested_role text not null default 'client',
  add column if not exists approval_status text not null default 'approved',
  add column if not exists requested_shop_name text,
  add column if not exists requested_shop_description text,
  add column if not exists approved_at timestamptz,
  add column if not exists rejection_reason text;

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
  req_role text := coalesce(nullif(trim(new.raw_user_meta_data ->> 'requested_role'), ''), 'client');
  req_shop_name text := nullif(trim(new.raw_user_meta_data ->> 'requested_shop_name'), '');
  req_shop_desc text := nullif(trim(new.raw_user_meta_data ->> 'requested_shop_description'), '');
  normalized_role text := case
    when lower(coalesce(new.email, new.raw_user_meta_data ->> 'email', '')) = 'paffpro01@gmail.com' then 'admin'
    else 'client'
  end;
  init_approval_status text := case
    when req_role = 'shop_owner' then 'pending'
    else 'approved'
  end;
begin
  perform public.assert_user_identity_available(
    new.id,
    normalized_name,
    normalized_phone,
    normalized_email
  );

  insert into public.users (id, name, phone, email, location, role, requested_role, approval_status, requested_shop_name, requested_shop_description)
  values (
    new.id,
    normalized_name,
    normalized_phone,
    normalized_email,
    normalized_location,
    normalized_role,
    req_role,
    init_approval_status,
    req_shop_name,
    req_shop_desc
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
      requested_role = coalesce(public.users.requested_role, excluded.requested_role),
      approval_status = coalesce(public.users.approval_status, excluded.approval_status),
      requested_shop_name = coalesce(public.users.requested_shop_name, excluded.requested_shop_name),
      requested_shop_description = coalesce(public.users.requested_shop_description, excluded.requested_shop_description);
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
  req_role text;
  req_shop_name text;
  req_shop_desc text;
  normalized_role text;
  init_approval_status text;
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
  req_role := coalesce(nullif(trim(auth_user.raw_user_meta_data ->> 'requested_role'), ''), 'client');
  req_shop_name := nullif(trim(auth_user.raw_user_meta_data ->> 'requested_shop_name'), '');
  req_shop_desc := nullif(trim(auth_user.raw_user_meta_data ->> 'requested_shop_description'), '');
  
  normalized_role := case
    when lower(coalesce(auth_user.email, auth_user.raw_user_meta_data ->> 'email', '')) = 'paffpro01@gmail.com' then 'admin'
    else 'client'
  end;
  
  init_approval_status := case
    when req_role = 'shop_owner' then 'pending'
    else 'approved'
  end;

  perform public.assert_user_identity_available(
    auth.uid(),
    normalized_name,
    normalized_phone,
    normalized_email
  );

  insert into public.users (id, name, phone, email, location, role, requested_role, approval_status, requested_shop_name, requested_shop_description)
  values (
    auth.uid(),
    normalized_name,
    normalized_phone,
    normalized_email,
    normalized_location,
    normalized_role,
    req_role,
    init_approval_status,
    req_shop_name,
    req_shop_desc
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
      requested_role = case 
        when public.users.requested_role = 'client' and excluded.requested_role = 'shop_owner' then 'shop_owner'
        else public.users.requested_role
      end,
      approval_status = case
        when public.users.requested_role = 'client' and excluded.requested_role = 'shop_owner' then 'pending'
        else public.users.approval_status
      end,
      requested_shop_name = coalesce(public.users.requested_shop_name, excluded.requested_shop_name),
      requested_shop_description = coalesce(public.users.requested_shop_description, excluded.requested_shop_description)
  returning * into ensured_user;

  return ensured_user;
end;
$$;

-- Run a one-time recovery to fix any shop applications that were lost before these functions were updated
do $$
begin
  update public.users u
  set 
    requested_role = 'shop_owner',
    approval_status = 'pending',
    requested_shop_name = nullif(trim(au.raw_user_meta_data ->> 'requested_shop_name'), ''),
    requested_shop_description = nullif(trim(au.raw_user_meta_data ->> 'requested_shop_description'), '')
  from auth.users au
  where u.id = au.id
    and u.requested_role = 'client'
    and coalesce(nullif(trim(au.raw_user_meta_data ->> 'requested_role'), ''), '') = 'shop_owner';
end;
$$;
