-- SQL script to revoke multi-tenant shop features and revert to a single-business model.
-- Run this in your Supabase SQL Editor.

-- 1. Reset all users to standard roles.
-- Convert any current 'shop_owner' back to 'client'. 
-- (Admins remain admins).
UPDATE public.users 
SET role = 'client' 
WHERE role = 'shop_owner';

-- Reset approval status and requested role for everyone.
UPDATE public.users
SET 
  requested_role = 'client',
  approval_status = 'approved',
  requested_shop_name = NULL,
  requested_shop_description = NULL,
  rejection_reason = NULL;

-- 2. Drop the multi-tenant specific RPC functions.
DROP FUNCTION IF EXISTS public.approve_shop_owner(uuid, text);
DROP FUNCTION IF EXISTS public.reject_shop_owner(uuid, text);

-- 3. Simplify the user creation logic to remove shop-approval checks.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized_name text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'name', '')), '');
  normalized_phone text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone', new.phone::text, '')), '');
  normalized_email text := nullif(trim(coalesce(new.email, new.raw_user_meta_data ->> 'email', '')), '');
  normalized_location text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'location', '')), '');
  normalized_role text := CASE
    WHEN lower(coalesce(new.email, new.raw_user_meta_data ->> 'email', '')) = 'paffpro01@gmail.com' THEN 'admin'
    ELSE 'client'
  END;
BEGIN
  PERFORM public.assert_user_identity_available(
    new.id,
    normalized_name,
    normalized_phone,
    normalized_email
  );

  INSERT INTO public.users (
    id,
    name,
    phone,
    email,
    location,
    role,
    requested_role,
    approval_status,
    created_at
  )
  VALUES (
    new.id,
    normalized_name,
    normalized_phone,
    normalized_email,
    normalized_location,
    normalized_role,
    'client',
    'approved',
    now()
  )
  ON CONFLICT (id) DO UPDATE
    SET
      name = COALESCE(excluded.name, public.users.name),
      phone = COALESCE(excluded.phone, public.users.phone),
      email = COALESCE(excluded.email, public.users.email),
      location = COALESCE(excluded.location, public.users.location),
      role = CASE
        WHEN lower(COALESCE(excluded.email, public.users.email, '')) = 'paffpro01@gmail.com' THEN 'admin'
        ELSE public.users.role
      END;
  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_current_user_profile()
RETURNS public.users
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  auth_user record;
  normalized_name text;
  normalized_phone text;
  normalized_email text;
  normalized_location text;
  normalized_role text;
  ensured_user public.users;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.';
  END IF;

  SELECT id, email, phone, raw_user_meta_data
  INTO auth_user
  FROM auth.users
  WHERE id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Authenticated user was not found.';
  END IF;

  normalized_name := nullif(trim(COALESCE(auth_user.raw_user_meta_data ->> 'name', '')), '');
  normalized_phone := nullif(trim(COALESCE(auth_user.raw_user_meta_data ->> 'phone', auth_user.phone::text, '')), '');
  normalized_email := nullif(trim(COALESCE(auth_user.email, auth_user.raw_user_meta_data ->> 'email', '')), '');
  normalized_location := nullif(trim(COALESCE(auth_user.raw_user_meta_data ->> 'location', '')), '');
  normalized_role := CASE
    WHEN lower(COALESCE(auth_user.email, auth_user.raw_user_meta_data ->> 'email', '')) = 'paffpro01@gmail.com' THEN 'admin'
    ELSE 'client'
  END;

  PERFORM public.assert_user_identity_available(
    auth.uid(),
    normalized_name,
    normalized_phone,
    normalized_email
  );

  INSERT INTO public.users (
    id,
    name,
    phone,
    email,
    location,
    role,
    requested_role,
    approval_status,
    created_at
  )
  VALUES (
    auth.uid(),
    normalized_name,
    normalized_phone,
    normalized_email,
    normalized_location,
    normalized_role,
    'client',
    'approved',
    now()
  )
  ON CONFLICT (id) DO UPDATE
    SET
      name = COALESCE(excluded.name, public.users.name),
      phone = COALESCE(excluded.phone, public.users.phone),
      email = COALESCE(excluded.email, public.users.email),
      location = COALESCE(excluded.location, public.users.location),
      role = CASE
        WHEN lower(COALESCE(excluded.email, public.users.email, '')) = 'paffpro01@gmail.com' THEN 'admin'
        ELSE public.users.role
      END
  RETURNING * INTO ensured_user;

  RETURN ensured_user;
END;
$$;
