-- Chama360 — Day 1 schema
-- Run this in Supabase SQL Editor (or via `supabase db push` once the CLI is linked).
-- Safe to re-run: uses IF NOT EXISTS / OR REPLACE where possible.

-- ============================================================
-- EXTENSIONS
-- ============================================================
create extension if not exists "pgcrypto"; -- gen_random_uuid()

-- ============================================================
-- 1. PROFILES  (mirrors auth.users, one row per signed-up person)
-- ============================================================
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  email       text,
  phone       text,
  avatar_url  text,
  created_at  timestamptz not null default now()
);

-- Auto-create a profile row whenever someone signs up via Supabase Auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- 2. CHAMAS  (a group / savings circle)
-- ============================================================
create table if not exists public.chamas (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  description  text,
  invite_code  text not null unique,
  currency     text not null default 'KES',
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);

-- ============================================================
-- 3. CHAMA_MEMBERS  (membership + role + running balance)
-- ============================================================
create table if not exists public.chama_members (
  id          uuid primary key default gen_random_uuid(),
  chama_id    uuid not null references public.chamas(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  role        text not null default 'member'
              check (role in ('chairperson','treasurer','secretary','member')),
  status      text not null default 'active'
              check (status in ('active','pending','removed')),
  balance     numeric(14,2) not null default 0,
  joined_at   timestamptz not null default now(),
  unique (chama_id, user_id)
);

-- ============================================================
-- 4. CONTRIBUTIONS
-- ============================================================
create table if not exists public.contributions (
  id                 uuid primary key default gen_random_uuid(),
  chama_id           uuid not null references public.chamas(id) on delete cascade,
  member_id          uuid not null references public.chama_members(id) on delete cascade,
  amount             numeric(14,2) not null check (amount > 0),
  contribution_date  date not null default current_date,
  method             text not null default 'manual', -- manual | mpesa (later)
  status             text not null default 'completed'
                     check (status in ('pending','completed','failed')),
  notes              text,
  recorded_by        uuid references public.profiles(id),
  created_at         timestamptz not null default now()
);

-- ============================================================
-- 5. LOANS
-- ============================================================
create table if not exists public.loans (
  id             uuid primary key default gen_random_uuid(),
  chama_id       uuid not null references public.chamas(id) on delete cascade,
  member_id      uuid not null references public.chama_members(id) on delete cascade,
  principal      numeric(14,2) not null check (principal > 0),
  interest_rate  numeric(5,2) not null default 0, -- percent, flat rate for MVP
  total_due      numeric(14,2) not null default 0,
  amount_repaid  numeric(14,2) not null default 0,
  status         text not null default 'pending'
                 check (status in ('pending','approved','rejected','active','repaid','defaulted')),
  purpose        text,
  approved_by    uuid references public.profiles(id),
  issued_at      timestamptz,
  due_date       date,
  created_at     timestamptz not null default now()
);

-- ============================================================
-- 6. LOAN_REPAYMENTS
-- ============================================================
create table if not exists public.loan_repayments (
  id           uuid primary key default gen_random_uuid(),
  loan_id      uuid not null references public.loans(id) on delete cascade,
  amount       numeric(14,2) not null check (amount > 0),
  repaid_at    timestamptz not null default now(),
  recorded_by  uuid references public.profiles(id)
);

-- ============================================================
-- 7. MEETINGS
-- ============================================================
create table if not exists public.meetings (
  id            uuid primary key default gen_random_uuid(),
  chama_id      uuid not null references public.chamas(id) on delete cascade,
  title         text not null,
  agenda        text,
  location      text,
  scheduled_at  timestamptz not null,
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now()
);

-- ============================================================
-- 8. ATTENDANCE
-- ============================================================
create table if not exists public.attendance (
  id          uuid primary key default gen_random_uuid(),
  meeting_id  uuid not null references public.meetings(id) on delete cascade,
  member_id   uuid not null references public.chama_members(id) on delete cascade,
  status      text not null default 'absent'
              check (status in ('present','absent','excused')),
  marked_at   timestamptz not null default now(),
  unique (meeting_id, member_id)
);

-- ============================================================
-- 9. ANNOUNCEMENTS
-- ============================================================
create table if not exists public.announcements (
  id          uuid primary key default gen_random_uuid(),
  chama_id    uuid not null references public.chamas(id) on delete cascade,
  title       text not null,
  body        text,
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now()
);

-- ============================================================
-- 10. TRANSACTIONS  (ledger — auto-populated by triggers below)
-- ============================================================
create table if not exists public.transactions (
  id             uuid primary key default gen_random_uuid(),
  chama_id       uuid not null references public.chamas(id) on delete cascade,
  member_id      uuid not null references public.chama_members(id) on delete cascade,
  type           text not null
                 check (type in ('contribution','loan_disbursement','loan_repayment','penalty','withdrawal')),
  amount         numeric(14,2) not null,
  reference_id   uuid,
  balance_after  numeric(14,2),
  created_at     timestamptz not null default now()
);

-- ============================================================
-- HELPER FUNCTIONS (used by RLS policies — security definer avoids recursive RLS)
-- ============================================================
create or replace function public.is_chama_member(p_chama_id uuid)
returns boolean
language sql security definer set search_path = public stable
as $$
  select exists (
    select 1 from public.chama_members
    where chama_id = p_chama_id
      and user_id = auth.uid()
      and status = 'active'
  );
$$;

create or replace function public.chama_role(p_chama_id uuid)
returns text
language sql security definer set search_path = public stable
as $$
  select role from public.chama_members
  where chama_id = p_chama_id and user_id = auth.uid() and status = 'active'
  limit 1;
$$;

create or replace function public.is_chama_admin(p_chama_id uuid)
returns boolean
language sql security definer set search_path = public stable
as $$
  select public.chama_role(p_chama_id) in ('chairperson','treasurer');
$$;

-- ============================================================
-- TRIGGERS: keep balance + transactions ledger in sync
-- ============================================================
create or replace function public.handle_new_contribution()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_new_balance numeric(14,2);
begin
  if new.status = 'completed' then
    update public.chama_members
      set balance = balance + new.amount
      where id = new.member_id
      returning balance into v_new_balance;

    insert into public.transactions (chama_id, member_id, type, amount, reference_id, balance_after)
    values (new.chama_id, new.member_id, 'contribution', new.amount, new.id, v_new_balance);
  end if;
  return new;
end;
$$;

drop trigger if exists on_contribution_created on public.contributions;
create trigger on_contribution_created
  after insert on public.contributions
  for each row execute procedure public.handle_new_contribution();

create or replace function public.handle_loan_repayment()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_chama_id uuid;
  v_member_id uuid;
  v_total_due numeric(14,2);
  v_repaid numeric(14,2);
begin
  select chama_id, member_id, total_due into v_chama_id, v_member_id, v_total_due
  from public.loans where id = new.loan_id;

  update public.loans
    set amount_repaid = amount_repaid + new.amount
    where id = new.loan_id
    returning amount_repaid into v_repaid;

  update public.loans
    set status = case when v_repaid >= v_total_due then 'repaid' else status end
    where id = new.loan_id;

  insert into public.transactions (chama_id, member_id, type, amount, reference_id)
  values (v_chama_id, v_member_id, 'loan_repayment', new.amount, new.id);

  return new;
end;
$$;

drop trigger if exists on_loan_repayment_created on public.loan_repayments;
create trigger on_loan_repayment_created
  after insert on public.loan_repayments
  for each row execute procedure public.handle_loan_repayment();

-- Compute total_due (principal + flat interest) whenever a loan becomes active.
create or replace function public.handle_loan_activation()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.status = 'active' and old.status is distinct from 'active' then
    new.total_due := new.principal + (new.principal * new.interest_rate / 100);
    new.issued_at := coalesce(new.issued_at, now());

    insert into public.transactions (chama_id, member_id, type, amount, reference_id)
    values (new.chama_id, new.member_id, 'loan_disbursement', new.principal, new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_loan_activated on public.loans;
create trigger on_loan_activated
  before update on public.loans
  for each row execute procedure public.handle_loan_activation();

-- ============================================================
-- RPC: join a chama by invite code (avoids exposing chamas table to non-members)
-- ============================================================
create or replace function public.join_chama_by_code(p_invite_code text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_chama_id uuid;
  v_member_id uuid;
begin
  select id into v_chama_id from public.chamas where invite_code = p_invite_code;

  if v_chama_id is null then
    raise exception 'Invalid invite code';
  end if;

  insert into public.chama_members (chama_id, user_id, role, status)
  values (v_chama_id, auth.uid(), 'member', 'active')
  on conflict (chama_id, user_id) do update set status = 'active'
  returning id into v_member_id;

  return v_chama_id;
end;
$$;

-- RPC: create a chama, auto-assign creator as chairperson
create or replace function public.create_chama(p_name text, p_description text default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_chama_id uuid;
  v_code text;
begin
  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

  insert into public.chamas (name, description, invite_code, created_by)
  values (p_name, p_description, v_code, auth.uid())
  returning id into v_chama_id;

  insert into public.chama_members (chama_id, user_id, role, status)
  values (v_chama_id, auth.uid(), 'chairperson', 'active');

  return v_chama_id;
end;
$$;

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table public.profiles         enable row level security;
alter table public.chamas           enable row level security;
alter table public.chama_members    enable row level security;
alter table public.contributions    enable row level security;
alter table public.loans            enable row level security;
alter table public.loan_repayments  enable row level security;
alter table public.meetings         enable row level security;
alter table public.attendance       enable row level security;
alter table public.announcements    enable row level security;
alter table public.transactions     enable row level security;

-- profiles: everyone signed in can view basic profiles (needed to show member names);
-- only the owner can update their own row.
drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated" on public.profiles
  for select using (auth.role() = 'authenticated');

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (id = auth.uid());

-- chamas: only members can read their chama's details.
-- Insert is only via the create_chama() RPC (security definer), so no direct insert policy.
drop policy if exists "chamas_select_member" on public.chamas;
create policy "chamas_select_member" on public.chamas
  for select using (public.is_chama_member(id));

-- chama_members: members can see the roster of their own chama.
-- Row insert happens only via join_chama_by_code()/create_chama() RPCs.
drop policy if exists "chama_members_select_same_chama" on public.chama_members;
create policy "chama_members_select_same_chama" on public.chama_members
  for select using (public.is_chama_member(chama_id));

drop policy if exists "chama_members_admin_update" on public.chama_members;
create policy "chama_members_admin_update" on public.chama_members
  for update using (public.is_chama_admin(chama_id));

-- contributions: members can view all contributions in their chama;
-- any active member can log their own contribution, admins can log for anyone.
drop policy if exists "contributions_select_member" on public.contributions;
create policy "contributions_select_member" on public.contributions
  for select using (public.is_chama_member(chama_id));

drop policy if exists "contributions_insert_member" on public.contributions;
create policy "contributions_insert_member" on public.contributions
  for insert with check (
    public.is_chama_member(chama_id)
    and (
      public.is_chama_admin(chama_id)
      or member_id in (select id from public.chama_members where chama_id = contributions.chama_id and user_id = auth.uid())
    )
  );

-- loans: members can view all loans in their chama; any member can request (insert pending);
-- only admins can update (approve/reject/activate).
drop policy if exists "loans_select_member" on public.loans;
create policy "loans_select_member" on public.loans
  for select using (public.is_chama_member(chama_id));

drop policy if exists "loans_insert_member" on public.loans;
create policy "loans_insert_member" on public.loans
  for insert with check (
    public.is_chama_member(chama_id)
    and member_id in (select id from public.chama_members where chama_id = loans.chama_id and user_id = auth.uid())
    and status = 'pending'
  );

drop policy if exists "loans_admin_update" on public.loans;
create policy "loans_admin_update" on public.loans
  for update using (public.is_chama_admin(chama_id));

-- loan_repayments: members can view repayments for loans in their chama; admins record repayments.
drop policy if exists "loan_repayments_select_member" on public.loan_repayments;
create policy "loan_repayments_select_member" on public.loan_repayments
  for select using (
    exists (select 1 from public.loans l where l.id = loan_repayments.loan_id and public.is_chama_member(l.chama_id))
  );

drop policy if exists "loan_repayments_admin_insert" on public.loan_repayments;
create policy "loan_repayments_admin_insert" on public.loan_repayments
  for insert with check (
    exists (select 1 from public.loans l where l.id = loan_repayments.loan_id and public.is_chama_admin(l.chama_id))
  );

-- meetings / attendance / announcements: readable by members, writable by admins.
drop policy if exists "meetings_select_member" on public.meetings;
create policy "meetings_select_member" on public.meetings
  for select using (public.is_chama_member(chama_id));

drop policy if exists "meetings_admin_write" on public.meetings;
create policy "meetings_admin_write" on public.meetings
  for insert with check (public.is_chama_admin(chama_id));

drop policy if exists "meetings_admin_update" on public.meetings;
create policy "meetings_admin_update" on public.meetings
  for update using (public.is_chama_admin(chama_id));

drop policy if exists "attendance_select_member" on public.attendance;
create policy "attendance_select_member" on public.attendance
  for select using (
    exists (select 1 from public.meetings m where m.id = attendance.meeting_id and public.is_chama_member(m.chama_id))
  );

drop policy if exists "attendance_admin_write" on public.attendance;
create policy "attendance_admin_write" on public.attendance
  for insert with check (
    exists (select 1 from public.meetings m where m.id = attendance.meeting_id and public.is_chama_admin(m.chama_id))
  );

drop policy if exists "attendance_admin_update" on public.attendance;
create policy "attendance_admin_update" on public.attendance
  for update using (
    exists (select 1 from public.meetings m where m.id = attendance.meeting_id and public.is_chama_admin(m.chama_id))
  );

drop policy if exists "announcements_select_member" on public.announcements;
create policy "announcements_select_member" on public.announcements
  for select using (public.is_chama_member(chama_id));

drop policy if exists "announcements_admin_write" on public.announcements;
create policy "announcements_admin_write" on public.announcements
  for insert with check (public.is_chama_admin(chama_id));

-- transactions: read-only ledger, visible to members of the chama. No direct insert
-- (rows are created only by the triggers above, running as security definer).
drop policy if exists "transactions_select_member" on public.transactions;
create policy "transactions_select_member" on public.transactions
  for select using (public.is_chama_member(chama_id));

-- ============================================================
-- INDEXES
-- ============================================================
create index if not exists idx_chama_members_chama on public.chama_members(chama_id);
create index if not exists idx_chama_members_user on public.chama_members(user_id);
create index if not exists idx_contributions_chama on public.contributions(chama_id, contribution_date desc);
create index if not exists idx_loans_chama on public.loans(chama_id, status);
create index if not exists idx_transactions_chama on public.transactions(chama_id, created_at desc);
create index if not exists idx_meetings_chama on public.meetings(chama_id, scheduled_at desc);
