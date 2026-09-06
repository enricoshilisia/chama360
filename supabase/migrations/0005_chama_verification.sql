-- Chama360 — staged chama registration with owner verification.
--
-- A chama is no longer usable the moment someone creates it. It lands in
-- 'pending_verification', the platform owner gets an email with a one-time
-- link, and only after that click can members be added or money recorded.
-- This is the gate that stops anyone from spinning up chamas on the
-- platform before we're ready to open it up.
--
-- Run after 0001-0004.

-- ============================================================
-- Registration state + the details collected by the wizard
-- ============================================================
alter table public.chamas
  add column if not exists status text not null default 'pending_verification'
    check (status in ('pending_verification','active','rejected')),
  add column if not exists contact_name text,
  add column if not exists contact_phone text,
  add column if not exists contact_email text,
  add column if not exists verification_token text,
  add column if not exists verification_sent_at timestamptz,
  add column if not exists verified_at timestamptz,
  add column if not exists rejected_reason text;

-- Anything that already exists predates this gate — don't lock out the
-- chama that's already live and in use.
update public.chamas set status = 'active', verified_at = now()
where status = 'pending_verification' and created_at < now();

create unique index if not exists idx_chamas_verification_token
  on public.chamas(verification_token) where verification_token is not null;

-- ============================================================
-- "Is this chama cleared to operate?" — used to gate every write
-- ============================================================
create or replace function public.is_chama_active(p_chama_id uuid)
returns boolean
language sql security definer set search_path = public stable
as $$
  select exists (
    select 1 from public.chamas where id = p_chama_id and status = 'active'
  );
$$;

-- ============================================================
-- create_chama now takes the wizard's fields and starts life pending.
--
-- The old two-argument version must go, not just be superseded. Postgres
-- overloads by signature, so it would survive alongside the new one — and
-- because the new one defaults its extra arguments, a two-argument call
-- becomes ambiguous and errors. Worse, anything reaching the old version
-- creates a chama with no verification token: permanently unapprovable.
-- ============================================================
drop function if exists public.create_chama(text, text);

create or replace function public.create_chama(
  p_name text,
  p_description text default null,
  p_contact_name text default null,
  p_contact_phone text default null,
  p_contact_email text default null
)
returns table (chama_id uuid, verification_token text)
language plpgsql security definer set search_path = public
as $$
declare
  v_chama_id uuid;
  v_code text;
  v_token text;
begin
  if exists (
    select 1 from public.chama_members
    where user_id = auth.uid() and status = 'active'
  ) then
    raise exception 'You can only be part of one chama for now';
  end if;

  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  -- 32 hex chars from two md5s — this is the only thing standing between a
  -- stranger and an approved chama, so it isn't a 6-character code.
  v_token := md5(gen_random_uuid()::text) || md5(gen_random_uuid()::text);

  insert into public.chamas (
    name, description, invite_code, created_by, status,
    contact_name, contact_phone, contact_email,
    verification_token, verification_sent_at
  )
  values (
    p_name, p_description, v_code, auth.uid(), 'pending_verification',
    p_contact_name, p_contact_phone, p_contact_email,
    v_token, now()
  )
  returning id into v_chama_id;

  insert into public.chama_members (chama_id, user_id, role, status)
  values (v_chama_id, auth.uid(), 'chairperson', 'active');

  return query select v_chama_id, v_token;
end;
$$;

-- ============================================================
-- Gate the writes. A pending chama can be looked at, not operated.
-- ============================================================
create or replace function public.add_managed_member(
  p_chama_id uuid,
  p_full_name text,
  p_phone text default null,
  p_role text default 'member'
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_member_id uuid;
begin
  if not public.is_chama_admin(p_chama_id) then
    raise exception 'Only the chairperson or treasurer can add members';
  end if;

  if not public.is_chama_active(p_chama_id) then
    raise exception 'This chama is still awaiting verification';
  end if;

  insert into public.chama_members (chama_id, user_id, full_name, phone, role, status)
  values (p_chama_id, null, p_full_name, p_phone, p_role, 'active')
  returning id into v_member_id;

  return v_member_id;
end;
$$;

create or replace function public.record_loan_for_member(
  p_chama_id uuid,
  p_member_id uuid,
  p_principal numeric,
  p_interest_rate numeric default 0,
  p_purpose text default null,
  p_due_date date default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_loan_id uuid;
begin
  if not public.is_chama_admin(p_chama_id) then
    raise exception 'Only the chairperson or treasurer can record a loan';
  end if;

  if not public.is_chama_active(p_chama_id) then
    raise exception 'This chama is still awaiting verification';
  end if;

  insert into public.loans (chama_id, member_id, principal, interest_rate, purpose, due_date, status, approved_by)
  values (p_chama_id, p_member_id, p_principal, p_interest_rate, p_purpose, p_due_date, 'pending', auth.uid())
  returning id into v_loan_id;

  update public.loans set status = 'active' where id = v_loan_id;

  return v_loan_id;
end;
$$;

-- Contributions go in through a plain insert, so the gate has to live in
-- the RLS policy rather than a function.
drop policy if exists "contributions_insert_member" on public.contributions;
create policy "contributions_insert_member" on public.contributions
  for insert with check (
    public.is_chama_member(chama_id)
    and public.is_chama_active(chama_id)
    and (
      public.is_chama_admin(chama_id)
      or member_id in (select id from public.chama_members where chama_id = contributions.chama_id and user_id = auth.uid())
    )
  );

-- Joining a pending chama by code shouldn't work either.
create or replace function public.join_chama_by_code(p_invite_code text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_chama_id uuid;
  v_member_id uuid;
begin
  if exists (
    select 1 from public.chama_members
    where user_id = auth.uid() and status = 'active'
  ) then
    raise exception 'You can only be part of one chama for now';
  end if;

  select id into v_chama_id from public.chamas where invite_code = p_invite_code;

  if v_chama_id is null then
    raise exception 'Invalid invite code';
  end if;

  if not public.is_chama_active(v_chama_id) then
    raise exception 'This chama is still awaiting verification';
  end if;

  insert into public.chama_members (chama_id, user_id, role, status)
  values (v_chama_id, auth.uid(), 'member', 'active')
  on conflict (chama_id, user_id) do update set status = 'active'
  returning id into v_member_id;

  return v_chama_id;
end;
$$;

-- ============================================================
-- Verification itself. SECURITY DEFINER so the verify-chama Edge Function
-- can call it with the anon key holding only the token — no service-role
-- key needed just to approve, and the token is the whole credential.
-- ============================================================
-- Returns the contact details as well as the name, so the Edge Function can
-- tell the chairperson their chama went live without a second query.
create or replace function public.verify_chama_by_token(p_token text)
returns table (
  chama_name text,
  contact_name text,
  contact_email text,
  already_verified boolean
)
language plpgsql security definer set search_path = public
as $$
declare
  v_chama record;
begin
  select * into v_chama from public.chamas where verification_token = p_token;

  if v_chama is null then
    raise exception 'Invalid or expired verification link';
  end if;

  if v_chama.status = 'active' then
    return query select v_chama.name, v_chama.contact_name, v_chama.contact_email, true;
    return;
  end if;

  update public.chamas
    set status = 'active', verified_at = now(), verification_token = null
    where id = v_chama.id;

  return query select v_chama.name, v_chama.contact_name, v_chama.contact_email, false;
end;
$$;

-- The chama's own members need to see its status to know they're waiting.
-- chamas_select_member already covers reading the row; nothing to add.
