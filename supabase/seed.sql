-- Optional demo data for local/dev setups.
-- Run this only if you want starter categories and products.

insert into public.categories (name)
values
  ('Washed Potatoes'),
  ('Unwashed / Mucoma')
on conflict (name) do nothing;

insert into public.products (
  name,
  description,
  image_url,
  price,
  discount_price,
  discount_threshold_kg,
  quantity,
  is_available
)
select *
from (
  values
    (
      'Washed Potatoes',
      'Clean premium potatoes prepared for direct household and restaurant use.',
      'https://images.unsplash.com/photo-1518977676601-b53f82aba655?auto=format&fit=crop&w=1200&q=80',
      650,
      620,
      25,
      320,
      true
    ),
    (
      'Unwashed Potatoes',
      'Fresh farm potatoes with natural skin, suitable for resale or bulk preparation.',
      'https://images.unsplash.com/photo-1590165482129-1b8b27698780?auto=format&fit=crop&w=1200&q=80',
      500,
      470,
      25,
      480,
      true
    )
) as seed(
  name,
  description,
  image_url,
  price,
  discount_price,
  discount_threshold_kg,
  quantity,
  is_available
)
where not exists (select 1 from public.products);

update public.products p
set category_id = c.id
from public.categories c
where p.category_id is null
  and (
    (lower(p.name) like '%washed%' and lower(c.name) = 'washed potatoes')
    or (
      (lower(p.name) like '%unwashed%' or lower(p.name) like '%mucoma%')
      and lower(c.name) = 'unwashed / mucoma'
    )
  );