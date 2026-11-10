-- Perry Family Christmas Lists: database schema
-- Tables are prefixed with xmas_ so they can live alongside other apps in one project.

create table if not exists public.xmas_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  created_at timestamptz not null default now()
);

create table if not exists public.xmas_items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.xmas_profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 200),
  link text check (link is null or char_length(link) <= 1000),
  notes text check (notes is null or char_length(notes) <= 1000),
  created_at timestamptz not null default now()
);
create index if not exists xmas_items_owner_idx on public.xmas_items(owner_id);

-- One claim per item. Hidden from the item's owner by RLS.
create table if not exists public.xmas_claims (
  item_id uuid primary key references public.xmas_items(id) on delete cascade,
  claimer_id uuid not null references public.xmas_profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists xmas_claims_claimer_idx on public.xmas_claims(claimer_id);

alter table public.xmas_profiles enable row level security;
alter table public.xmas_items enable row level security;
alter table public.xmas_claims enable row level security;

-- Profiles: any signed-in family member can see names; you can only rename yourself.
create policy "xmas profiles readable" on public.xmas_profiles
  for select to authenticated using (true);
create policy "xmas profiles self update" on public.xmas_profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Items: everyone signed in can read; only the owner can add, change or delete.
create policy "xmas items readable" on public.xmas_items
  for select to authenticated using (true);
create policy "xmas items owner insert" on public.xmas_items
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "xmas items owner update" on public.xmas_items
  for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "xmas items owner delete" on public.xmas_items
  for delete to authenticated using (owner_id = (select auth.uid()));

-- Claims: visible to everyone except the person whose list it is.
create policy "xmas claims hidden from owner" on public.xmas_claims
  for select to authenticated using (
    exists (select 1 from public.xmas_items i
            where i.id = item_id and i.owner_id <> (select auth.uid()))
  );
create policy "xmas claims insert" on public.xmas_claims
  for insert to authenticated with check (
    claimer_id = (select auth.uid())
    and exists (select 1 from public.xmas_items i
                where i.id = item_id and i.owner_id <> (select auth.uid()))
  );
create policy "xmas claims undo own" on public.xmas_claims
  for delete to authenticated using (claimer_id = (select auth.uid()));

-- Create a profile automatically when someone signs up with a display name.
create or replace function public.xmas_handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.raw_user_meta_data ? 'xmas_display_name' then
    insert into public.xmas_profiles (id, display_name)
    values (new.id, left(new.raw_user_meta_data->>'xmas_display_name', 40))
    on conflict (id) do nothing;
  end if;
  return new;
end $$;
revoke execute on function public.xmas_handle_new_user() from public, anon, authenticated;

drop trigger if exists xmas_on_auth_user_created on auth.users;
create trigger xmas_on_auth_user_created
  after insert on auth.users
  for each row execute function public.xmas_handle_new_user();

-- Lets an existing user (e.g. from another app in the same project) join with a name.
create policy "xmas profiles self insert" on public.xmas_profiles
  for insert to authenticated with check (id = (select auth.uid()));
