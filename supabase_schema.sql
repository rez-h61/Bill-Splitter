-- ==============================================================================
-- SUPABASE FULL-STACK DATABASE SCHEMA FOR BILL SPLITTER
-- ==============================================================================
-- Run this entire script in your Supabase SQL Editor (Dashboard > SQL Editor)
-- ==============================================================================

-- 1. Create public.users table (mirrors auth.users profile)
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 2. Create public.bills table
create table if not exists public.bills (
  id uuid primary key default gen_random_uuid(),
  created_by uuid references public.users(id) on delete cascade not null,
  title text default 'Bill Split',
  total_amount numeric(10, 2) not null default 0.00,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 3. Create public.bill_items table
create table if not exists public.bill_items (
  id uuid primary key default gen_random_uuid(),
  bill_id uuid not null references public.bills(id) on delete cascade,
  name text not null,
  price numeric(10, 2) not null default 0.00,
  shared_by jsonb default '[]'::jsonb,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 4. Create public.debts table
create table if not exists public.debts (
  id uuid primary key default gen_random_uuid(),
  bill_id uuid references public.bills(id) on delete cascade,
  debtor_id uuid references public.users(id) on delete set null,
  debtor_name text not null,
  creditor_id uuid references public.users(id) on delete set null,
  creditor_name text not null,
  amount numeric(10, 2) not null default 0.00,
  status text not null default 'pending' check (status in ('pending', 'paid')),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 5. Trigger function to automatically insert new auth user into public.users
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = coalesce(excluded.display_name, public.users.display_name);
  return new;
end;
$$ language plpgsql security definer;

-- Recreate trigger cleanly
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 6. Enable Row Level Security (RLS) on all tables
alter table public.users enable row level security;
alter table public.bills enable row level security;
alter table public.bill_items enable row level security;
alter table public.debts enable row level security;

-- 7. RLS Policies: users
drop policy if exists "Allow all users to read profiles" on public.users;
create policy "Allow all users to read profiles"
  on public.users for select
  to authenticated, anon
  using (true);

drop policy if exists "Allow users to update own profile" on public.users;
create policy "Allow users to update own profile"
  on public.users for update
  to authenticated
  using (auth.uid() = id);

drop policy if exists "Allow users to insert own profile" on public.users;
create policy "Allow users to insert own profile"
  on public.users for insert
  to authenticated
  with check (auth.uid() = id);

-- 8. RLS Policies: bills
drop policy if exists "Allow users to select own bills" on public.bills;
create policy "Allow users to select own bills"
  on public.bills for select
  to authenticated
  using (created_by = auth.uid());

drop policy if exists "Allow users to insert own bills" on public.bills;
create policy "Allow users to insert own bills"
  on public.bills for insert
  to authenticated
  with check (created_by = auth.uid());

drop policy if exists "Allow users to delete own bills" on public.bills;
create policy "Allow users to delete own bills"
  on public.bills for delete
  to authenticated
  using (created_by = auth.uid());

-- 9. RLS Policies: bill_items
drop policy if exists "Allow users to select bill items" on public.bill_items;
create policy "Allow users to select bill items"
  on public.bill_items for select
  to authenticated
  using (
    exists (
      select 1 from public.bills
      where public.bills.id = public.bill_items.bill_id
      and public.bills.created_by = auth.uid()
    )
  );

drop policy if exists "Allow users to insert bill items" on public.bill_items;
create policy "Allow users to insert bill items"
  on public.bill_items for insert
  to authenticated
  with check (
    exists (
      select 1 from public.bills
      where public.bills.id = public.bill_items.bill_id
      and public.bills.created_by = auth.uid()
    )
  );

drop policy if exists "Allow users to delete bill items" on public.bill_items;
create policy "Allow users to delete bill items"
  on public.bill_items for delete
  to authenticated
  using (
    exists (
      select 1 from public.bills
      where public.bills.id = public.bill_items.bill_id
      and public.bills.created_by = auth.uid()
    )
  );

-- 10. RLS Policies: debts
drop policy if exists "Allow users to view their debts" on public.debts;
create policy "Allow users to view their debts"
  on public.debts for select
  to authenticated
  using (
    creditor_id = auth.uid()
    or debtor_id = auth.uid()
    or exists (
      select 1 from public.bills
      where public.bills.id = public.debts.bill_id
      and public.bills.created_by = auth.uid()
    )
  );

drop policy if exists "Allow users to insert debts" on public.debts;
create policy "Allow users to insert debts"
  on public.debts for insert
  to authenticated
  with check (
    creditor_id = auth.uid()
    or debtor_id = auth.uid()
    or exists (
      select 1 from public.bills
      where public.bills.id = public.debts.bill_id
      and public.bills.created_by = auth.uid()
    )
  );

drop policy if exists "Allow users to update debt status" on public.debts;
create policy "Allow users to update debt status"
  on public.debts for update
  to authenticated
  using (
    creditor_id = auth.uid()
    or debtor_id = auth.uid()
    or exists (
      select 1 from public.bills
      where public.bills.id = public.debts.bill_id
      and public.bills.created_by = auth.uid()
    )
  );

drop policy if exists "Allow users to delete debts" on public.debts;
create policy "Allow users to delete debts"
  on public.debts for delete
  to authenticated
  using (
    creditor_id = auth.uid()
    or exists (
      select 1 from public.bills
      where public.bills.id = public.debts.bill_id
      and public.bills.created_by = auth.uid()
    )
  );
