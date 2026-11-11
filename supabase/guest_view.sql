-- Guest view: a secret link (?guest=CODE) lets people without an account see
-- every list read-only. Bought items are flagged, but never who bought them.
-- The code lives in xmas_guest_access (no RLS policies, so nobody can read it
-- through the API). To change the link:
--   update public.xmas_guest_access set code = replace(gen_random_uuid()::text, '-', '');

create table if not exists public.xmas_guest_access (
  id int primary key default 1 check (id = 1),
  code text not null,
  created_at timestamptz not null default now()
);
alter table public.xmas_guest_access enable row level security;

insert into public.xmas_guest_access (id, code)
values (1, replace(gen_random_uuid()::text, '-', ''))
on conflict (id) do nothing;

create or replace function public.xmas_guest_view(p_code text)
returns json language plpgsql stable security definer set search_path = '' as $$
begin
  if p_code is null or not exists (select 1 from public.xmas_guest_access g where g.code = p_code) then
    raise exception 'invalid guest link' using errcode = '28000';
  end if;
  return coalesce((
    select json_agg(json_build_object(
      'name', p.display_name,
      'items', coalesce((
        select json_agg(json_build_object(
          'title', i.title, 'link', i.link, 'notes', i.notes,
          'bought', exists (select 1 from public.xmas_claims c where c.item_id = i.id)
        ) order by i.created_at)
        from public.xmas_items i where i.owner_id = p.id), '[]'::json)
    ) order by p.display_name)
    from public.xmas_profiles p), '[]'::json);
end $$;
revoke execute on function public.xmas_guest_view(text) from public;
grant execute on function public.xmas_guest_view(text) to anon, authenticated;
