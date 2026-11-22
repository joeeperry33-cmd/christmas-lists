-- Item ranking: each owner orders their own list so family can see what's most wanted.
-- rank 1 = most wanted. Existing items keep the order they were added in.

alter table public.xmas_items add column if not exists rank int;

update public.xmas_items i set rank = r.rn
from (select id, row_number() over (partition by owner_id order by created_at, id) as rn
      from public.xmas_items) r
where i.id = r.id and i.rank is null;

-- New items go to the bottom of the owner's list.
create or replace function public.xmas_items_default_rank()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.rank is null then
    select coalesce(max(rank), 0) + 1 into new.rank
    from public.xmas_items where owner_id = new.owner_id;
  end if;
  return new;
end $$;

drop trigger if exists xmas_items_default_rank on public.xmas_items;
create trigger xmas_items_default_rank
  before insert on public.xmas_items
  for each row execute function public.xmas_items_default_rank();

alter table public.xmas_items alter column rank set not null;
create index if not exists xmas_items_owner_rank_idx on public.xmas_items(owner_id, rank);

-- Save a new order in one call: pass your item ids, most wanted first.
-- Runs as the caller, so RLS still limits it to your own items.
create or replace function public.xmas_reorder_items(p_ids uuid[])
returns void language sql security invoker set search_path = '' as $$
  update public.xmas_items i set rank = t.ord
  from unnest(p_ids) with ordinality as t(id, ord)
  where i.id = t.id and i.owner_id = (select auth.uid());
$$;
revoke execute on function public.xmas_reorder_items(uuid[]) from public, anon;
grant execute on function public.xmas_reorder_items(uuid[]) to authenticated;

-- Guest view: same data as before, now in ranked order with the rank included.
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
          'title', i.title, 'link', i.link, 'notes', i.notes, 'rank', i.rank,
          'bought', exists (select 1 from public.xmas_claims c where c.item_id = i.id)
        ) order by i.rank, i.created_at)
        from public.xmas_items i where i.owner_id = p.id), '[]'::json)
    ) order by p.display_name)
    from public.xmas_profiles p), '[]'::json);
end $$;
