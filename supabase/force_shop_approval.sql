insert into public.users (id, name, phone, email, location, role, requested_role, approval_status, requested_shop_name, requested_shop_description)
select 
  id, 
  coalesce(nullif(trim(raw_user_meta_data->>'name'), ''), 'Applicant'),
  coalesce(nullif(trim(raw_user_meta_data->>'phone'), ''), phone, '0000000000'),
  email,
  coalesce(nullif(trim(raw_user_meta_data->>'location'), ''), 'Unknown'),
  'client',
  'shop_owner',
  'pending',
  coalesce(nullif(trim(raw_user_meta_data->>'requested_shop_name'), ''), 'My Shop'),
  coalesce(nullif(trim(raw_user_meta_data->>'requested_shop_description'), ''), 'Please approve my shop')
from auth.users
where email = 'paffdadd07@gmail.com'
on conflict (id) do update
set 
  requested_role = 'shop_owner',
  approval_status = 'pending',
  requested_shop_name = coalesce(public.users.requested_shop_name, excluded.requested_shop_name),
  requested_shop_description = coalesce(public.users.requested_shop_description, excluded.requested_shop_description);
