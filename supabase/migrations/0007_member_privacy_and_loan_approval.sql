-- Chama360 — members stop seeing each other's money, and loan requests
-- become something an admin can act on.
--
-- PART 1 is a security fix, not a UI change. Until now every SELECT policy
-- on the money tables said "is_chama_member(chama_id)", which means any
-- member could read every other member's contributions, loans, repayments
-- and balance by calling the REST API directly with the anon key — and
-- that key ships inside the APK, so it is public by construction. Hiding
-- the figures in the app would have left the data readable.
--
-- Run after 0001-0006.

-- ============================================================
-- PART 1 — each member sees their own money; admins see the chama's
-- ============================================================

-- Contributions ------------------------------------------------------
drop policy if exists "contributions_select_member" on public.contributions;
create policy "contributions_select_own_or_admin" on public.contributions
  for select using (
    public.is_chama_admin(chama_id)
    or member_id in (
      select id from public.chama_members
      where chama_id = contributions.chama_id and user_id = auth.uid()
    )
  );

-- Ledger -------------------------------------------------------------
drop policy if exists "transactions_select_member" on public.transactions;
create policy "transactions_select_own_or_admin" on public.transactions
  for select using (
    public.is_chama_admin(chama_id)
    or member_id in (
      select id from public.chama_members
      where chama_id = transactions.chama_id and user_id = auth.uid()
    )
  );

-- Loans --------------------------------------------------------------
drop policy if exists "loans_select_member" on public.loans;
create policy "loans_select_own_or_admin" on public.loans
  for select using (
    public.is_chama_admin(chama_id)
    or member_id in (
      select id from public.chama_members
      where chama_id = loans.chama_id and user_id = auth.uid()
    )
  );

-- Repayments ---------------------------------------------------------
drop policy if exists "loan_repayments_select_member" on public.loan_repayments;
create policy "loan_repayments_select_own_or_admin" on public.loan_repayments
  for select using (
    exists (
      select 1 from public.loans l
      where l.id = loan_repayments.loan_id
        and (
          public.is_chama_admin(l.chama_id)
          or l.member_id in (
            select id from public.chama_members
            where chama_id = l.chama_id and user_id = auth.uid()
          )
        )
    )
  );

-- Membership rows ----------------------------------------------------
-- Balance lives on this table and Postgres RLS is row-level, not
-- column-level, so the only way to stop a member reading balances is to
-- stop them reading other people's rows at all. The roster they *do*
-- need — names and roles — comes from chama_roster() below, which is
-- SECURITY DEFINER and returns no balances unless you're an admin.
drop policy if exists "chama_members_select_same_chama" on public.chama_members;
create policy "chama_members_select_own_or_admin" on public.chama_members
  for select using (
    user_id = auth.uid() or public.is_chama_admin(chama_id)
  );

-- ============================================================
-- The roster every member is allowed to see: who else is here, and in
-- what role. Amounts are withheld unless the caller is an admin or it is
-- their own row.
-- ============================================================
create or replace function public.chama_roster(p_chama_id uuid)
returns table (
  id uuid,
  user_id uuid,
  role text,
  display_name text,
  phone text,
  has_account boolean,
  balance numeric,
  is_self boolean
)
language plpgsql security definer set search_path = public stable
as $$
declare
  v_is_admin boolean;
begin
  if not public.is_chama_member(p_chama_id) then
    raise exception 'Not a member of this chama';
  end if;

  v_is_admin := public.is_chama_admin(p_chama_id);

  return query
  select
    m.id,
    m.user_id,
    m.role,
    coalesce(nullif(trim(p.full_name), ''), m.full_name, p.email, 'Member') as display_name,
    case when v_is_admin or m.user_id = auth.uid() then coalesce(m.phone, p.phone) end as phone,
    (m.user_id is not null) as has_account,
    case when v_is_admin or m.user_id = auth.uid() then m.balance end as balance,
    (m.user_id = auth.uid()) as is_self
  from public.chama_members m
  left join public.profiles p on p.id = m.user_id
  where m.chama_id = p_chama_id and m.status = 'active'
  order by
    case m.role when 'chairperson' then 0 when 'treasurer' then 1
                when 'secretary' then 2 else 3 end,
    display_name;
end;
$$;

grant execute on function public.chama_roster(uuid) to authenticated;

-- ============================================================
-- Chama-level totals. A member can't see who contributed what, but the
-- pooled figures are the whole point of belonging to a chama, so those
-- stay visible to everyone in it.
-- ============================================================
create or replace function public.chama_totals(p_chama_id uuid)
returns table (
  total_contributions numeric,
  member_count integer,
  total_loans_disbursed numeric,
  total_outstanding numeric,
  active_loan_count integer
)
language plpgsql security definer set search_path = public stable
as $$
begin
  if not public.is_chama_member(p_chama_id) then
    raise exception 'Not a member of this chama';
  end if;

  return query
  select
    coalesce((select sum(c.amount) from public.contributions c
              where c.chama_id = p_chama_id and c.status = 'completed'), 0),
    (select count(*)::integer from public.chama_members m
     where m.chama_id = p_chama_id and m.status = 'active'),
    coalesce((select sum(l.principal) from public.loans l
              where l.chama_id = p_chama_id
                and l.status in ('active', 'repaid', 'defaulted')), 0),
    coalesce((select sum(greatest(l.total_due - l.amount_repaid, 0)) from public.loans l
              where l.chama_id = p_chama_id and l.status = 'active'), 0),
    (select count(*)::integer from public.loans l
     where l.chama_id = p_chama_id and l.status = 'active');
end;
$$;

grant execute on function public.chama_totals(uuid) to authenticated;

-- ============================================================
-- PART 2 — loan requests an admin can act on
-- ============================================================

alter table public.loans
  add column if not exists rejection_reason text,
  add column if not exists decided_at timestamptz,
  add column if not exists decided_by uuid references public.profiles(id);

-- Notifications gain a target, so tapping one can open the thing it is
-- about instead of dropping the reader on a list to go hunting.
alter table public.notifications
  add column if not exists link_type text,
  add column if not exists link_id uuid;

-- A new request has to reach the people who can approve it. The existing
-- trigger only told the borrower their own status changed, which nobody
-- was waiting for.
create or replace function public.handle_loan_request_notification()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if new.status <> 'pending' then
    return new;
  end if;

  select coalesce(nullif(trim(p.full_name), ''), m.full_name, p.email, 'A member')
    into v_name
  from public.chama_members m
  left join public.profiles p on p.id = m.user_id
  where m.id = new.member_id;

  -- Linked to the member rather than the loan: an admin deciding on a
  -- request wants to see who is asking and what they have contributed,
  -- not just the number they typed.
  insert into public.notifications (user_id, chama_id, title, body, link_type, link_id)
  select
    m.user_id,
    new.chama_id,
    'Loan request',
    v_name || ' has requested ' || to_char(new.principal, 'FM999,999,990') ||
      case when new.purpose is null or new.purpose = '' then ''
           else ' for ' || new.purpose end,
    'loan_request',
    new.member_id
  from public.chama_members m
  where m.chama_id = new.chama_id
    and m.status = 'active'
    and m.role in ('chairperson', 'treasurer')
    and m.user_id is not null;

  return new;
end;
$$;

drop trigger if exists on_loan_requested on public.loans;
create trigger on_loan_requested
  after insert on public.loans
  for each row execute procedure public.handle_loan_request_notification();

-- Telling a borrower "rejected" without saying why is how a chairperson
-- ends up explaining it by phone anyway. The reason is mandatory here, so
-- it always travels with the decision.
create or replace function public.reject_loan(p_loan_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_loan record;
begin
  select * into v_loan from public.loans where id = p_loan_id;
  if v_loan is null then
    raise exception 'Loan not found';
  end if;
  if not public.is_chama_admin(v_loan.chama_id) then
    raise exception 'Only the chairperson or treasurer can decide on a loan';
  end if;
  if length(coalesce(trim(p_reason), '')) < 3 then
    raise exception 'Give a reason for the rejection';
  end if;
  if v_loan.status = 'active' or v_loan.status = 'repaid' then
    raise exception 'This loan has already been disbursed';
  end if;

  update public.loans
    set status = 'rejected',
        rejection_reason = trim(p_reason),
        decided_at = now(),
        decided_by = auth.uid()
    where id = p_loan_id;

  insert into public.notifications (user_id, chama_id, title, body, link_type, link_id)
  select m.user_id, v_loan.chama_id, 'Loan not approved',
         'Your request was not approved: ' || trim(p_reason),
         'loan', p_loan_id
  from public.chama_members m
  where m.id = v_loan.member_id and m.user_id is not null;
end;
$$;

grant execute on function public.reject_loan(uuid, text) to authenticated;

-- Approving covers re-approving something previously rejected: the
-- rejection reason is cleared so a stale explanation can't linger on a
-- loan that was subsequently granted.
create or replace function public.approve_loan(
  p_loan_id uuid,
  p_interest_rate numeric default 0,
  p_due_date date default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_loan record;
begin
  select * into v_loan from public.loans where id = p_loan_id;
  if v_loan is null then
    raise exception 'Loan not found';
  end if;
  if not public.is_chama_admin(v_loan.chama_id) then
    raise exception 'Only the chairperson or treasurer can decide on a loan';
  end if;
  if v_loan.status = 'active' or v_loan.status = 'repaid' then
    raise exception 'This loan has already been disbursed';
  end if;

  -- Setting status to 'active' fires handle_loan_activation, which
  -- computes total_due and writes the disbursement into the ledger.
  update public.loans
    set interest_rate = coalesce(p_interest_rate, 0),
        due_date = p_due_date,
        rejection_reason = null,
        status = 'active',
        approved_by = auth.uid(),
        decided_at = now(),
        decided_by = auth.uid()
    where id = p_loan_id;

  insert into public.notifications (user_id, chama_id, title, body, link_type, link_id)
  select m.user_id, v_loan.chama_id, 'Loan approved',
         'Your loan of ' || to_char(v_loan.principal, 'FM999,999,990') ||
           ' has been approved.',
         'loan', p_loan_id
  from public.chama_members m
  where m.id = v_loan.member_id and m.user_id is not null;
end;
$$;

grant execute on function public.approve_loan(uuid, numeric, date) to authenticated;
