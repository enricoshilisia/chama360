-- Chama360 — chairperson-managed members (no app account required)
--
-- Today's real use case: one chairperson runs the app; everyone else is a
-- record they manage (add a member, record their contributions, record
-- loans for them) with no login of their own. Later, when other people
-- start self-registering and running their own chamas, that flow keeps
-- working unchanged — a chama_members row just gets a real user_id instead
-- of NULL. Both kinds of rows coexist in the same table from day one.
--
-- Run after 0001_init_schema.sql and 0002_notifications.sql.

alter table public.chama_members
  alter column user_id drop not null;

alter table public.chama_members
  add column if not exists full_name text,
  add column if not exists phone text;

-- A row must be identifiable one way or the other: either it's a real
-- account (user_id) or the chairperson recorded a name for it.
alter table public.chama_members drop constraint if exists chama_members_identity_check;
alter table public.chama_members
  add constraint chama_members_identity_check check (user_id is not null or full_name is not null);

-- is_chama_member / is_chama_admin / chama_role all key off
-- "user_id = auth.uid()", so a managed member (user_id null) already can't
-- authenticate as themselves and gets zero access automatically — no RLS
-- change needed for that part.

-- RPC: chairperson/treasurer adds someone who has no app account of their
-- own. Runs as the function owner, same bypass-RLS pattern as
-- create_chama()/join_chama_by_code() in 0001.
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

  insert into public.chama_members (chama_id, user_id, full_name, phone, role, status)
  values (p_chama_id, null, p_full_name, p_phone, p_role, 'active')
  returning id into v_member_id;

  return v_member_id;
end;
$$;

-- RPC: admin records a loan directly as disbursed. Skips the
-- request-then-approve dance (there's no one else to approve it when the
-- borrower has no account to request through) by inserting pending and
-- immediately flipping to active, which fires the existing
-- handle_loan_activation trigger (computes total_due, logs the
-- disbursement) exactly as the normal approve-and-disburse path does.
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

  insert into public.loans (chama_id, member_id, principal, interest_rate, purpose, due_date, status, approved_by)
  values (p_chama_id, p_member_id, p_principal, p_interest_rate, p_purpose, p_due_date, 'pending', auth.uid())
  returning id into v_loan_id;

  update public.loans set status = 'active' where id = v_loan_id;

  return v_loan_id;
end;
$$;
