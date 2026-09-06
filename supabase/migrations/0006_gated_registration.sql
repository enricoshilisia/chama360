-- Chama360 — approval before account.
--
-- 0005 let a chairperson sign up, confirm their email, log in, and only
-- then wait for approval. That means an account existed on the platform
-- before the owner had agreed to anything. This inverts it:
--
--   1. Anyone can submit a registration  (no account, no login)
--   2. The owner is emailed and approves  (Resend)
--   3. Only then is an account created and Supabase emails the invite
--   4. The chairperson sets their password and finds their chama waiting
--
-- Public signup is disabled alongside this migration, so an account can
-- only come into being through step 3 or through a chairperson creating a
-- login for one of their own members.
--
-- Run after 0001-0005.

-- ============================================================
-- Applications live here until approved. Deliberately separate from
-- `chamas`: a chama has an owner, and until approval there is no owner.
-- ============================================================
create table if not exists public.chama_registrations (
  id                  uuid primary key default gen_random_uuid(),
  chama_name          text not null,
  description         text,
  contact_name        text not null,
  contact_phone       text not null,
  contact_email       text not null,
  status              text not null default 'pending'
                      check (status in ('pending','approved','rejected')),
  verification_token  text unique,
  chama_id            uuid references public.chamas(id) on delete set null,
  rejected_reason     text,
  created_at          timestamptz not null default now(),
  reviewed_at         timestamptz
);

create index if not exists idx_chama_registrations_status
  on public.chama_registrations(status, created_at desc);

alter table public.chama_registrations enable row level security;

-- No policies at all: nothing reaches this table through the client API.
-- Submissions go through submit_chama_registration() and approvals through
-- approve_chama_registration(), both SECURITY DEFINER. That keeps a
-- stranger from reading other people's contact details, which is exactly
-- what this table is full of.

-- ============================================================
-- Step 1 — a stranger submits an application.
-- Callable by anon; that's the point. It returns only the token needed to
-- build the owner's approval link, never other rows.
-- ============================================================
create or replace function public.submit_chama_registration(
  p_chama_name text,
  p_contact_name text,
  p_contact_phone text,
  p_contact_email text,
  p_description text default null
)
returns table (registration_id uuid, verification_token text)
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
  v_token text;
begin
  if length(coalesce(trim(p_chama_name), '')) < 3 then
    raise exception 'Enter the name of the chama';
  end if;
  if length(coalesce(trim(p_contact_name), '')) < 3 then
    raise exception 'Enter the chairperson''s name';
  end if;
  if position('@' in coalesce(p_contact_email, '')) = 0 then
    raise exception 'Enter a valid email address';
  end if;

  -- One open application per email. Without this, a refresh-happy
  -- applicant floods the owner's inbox with approval links that all
  -- provision separate chamas.
  if exists (
    select 1 from public.chama_registrations
    where lower(contact_email) = lower(trim(p_contact_email)) and status = 'pending'
  ) then
    raise exception 'A registration for this email is already awaiting review';
  end if;

  v_token := md5(gen_random_uuid()::text) || md5(gen_random_uuid()::text);

  insert into public.chama_registrations (
    chama_name, description, contact_name, contact_phone, contact_email, verification_token
  )
  values (
    trim(p_chama_name), nullif(trim(coalesce(p_description, '')), ''),
    trim(p_contact_name), trim(p_contact_phone), lower(trim(p_contact_email)), v_token
  )
  returning id into v_id;

  return query select v_id, v_token;
end;
$$;

grant execute on function public.submit_chama_registration(text, text, text, text, text)
  to anon, authenticated;

-- ============================================================
-- Step 3 — the owner has approved. Provision the chama and hand back the
-- details the Edge Function needs to invite the chairperson.
--
-- The account itself is created by the Edge Function (admin API), not
-- here — SQL can't create auth users. This runs first so that by the time
-- the invite email lands, the chama is already there.
-- ============================================================
create or replace function public.approve_chama_registration(p_token text)
returns table (
  registration_id uuid,
  chama_id uuid,
  chama_name text,
  contact_name text,
  contact_email text,
  already_approved boolean
)
language plpgsql security definer set search_path = public
as $$
declare
  v_reg record;
  v_chama_id uuid;
  v_code text;
begin
  select * into v_reg from public.chama_registrations where verification_token = p_token;

  if v_reg is null then
    raise exception 'Invalid or expired approval link';
  end if;

  if v_reg.status = 'approved' then
    return query select v_reg.id, v_reg.chama_id, v_reg.chama_name,
                        v_reg.contact_name, v_reg.contact_email, true;
    return;
  end if;

  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

  -- created_by stays null until the chairperson's account exists; the Edge
  -- Function fills it in along with their membership row.
  insert into public.chamas (
    name, description, invite_code, status,
    contact_name, contact_phone, contact_email, verified_at
  )
  values (
    v_reg.chama_name, v_reg.description, v_code, 'active',
    v_reg.contact_name, v_reg.contact_phone, v_reg.contact_email, now()
  )
  returning id into v_chama_id;

  update public.chama_registrations
    set status = 'approved',
        chama_id = v_chama_id,
        reviewed_at = now(),
        verification_token = null
    where id = v_reg.id;

  return query select v_reg.id, v_chama_id, v_reg.chama_name,
                      v_reg.contact_name, v_reg.contact_email, false;
end;
$$;

-- ============================================================
-- Step 4 — the invited chairperson's account now exists; attach them.
-- Called by the Edge Function once the auth user has been created.
-- ============================================================
create or replace function public.attach_chairperson(p_chama_id uuid, p_user_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.chamas set created_by = p_user_id
  where id = p_chama_id and created_by is null;

  insert into public.chama_members (chama_id, user_id, role, status)
  values (p_chama_id, p_user_id, 'chairperson', 'active')
  on conflict (chama_id, user_id) do update
    set role = 'chairperson', status = 'active';
end;
$$;
