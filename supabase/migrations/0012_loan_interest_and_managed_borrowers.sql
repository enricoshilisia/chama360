-- Three things about loans.
--
-- 1. A chairperson could not record a loan for a member who has no app
--    login — which is most members, and the whole point of the
--    chairperson-managed model. It read as a permission problem; it was
--    not. handle_loan_status_notification looked up the borrower's
--    account and inserted a notification addressed to it without checking
--    that one existed, so for a managed member user_id came back null,
--    notifications.user_id is NOT NULL, and the whole loan rolled back.
--    Members with logins were unaffected, which is why it went unnoticed.
--
-- 2. An interest rate meant nothing without a period. "10%" could be the
--    whole cost of the loan or 10% every month, and the two differ by a
--    factor of the loan's length.
--
-- 3. Interest the chama earns is income, and was counted nowhere.

-- ------------------------------------------------- 1. managed borrowers

create or replace function public.handle_loan_status_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  if new.status is distinct from old.status then
    select user_id into v_user_id from public.chama_members where id = new.member_id;

    -- A member the chairperson manages has no account to notify. Their
    -- record still updates; there is simply nobody to send a message to.
    if v_user_id is not null then
      insert into public.notifications (user_id, chama_id, title, body, link_type, link_id)
      values (
        v_user_id,
        new.chama_id,
        'Loan update',
        'Your loan request is now: ' || new.status,
        'loan',
        new.id
      );
    end if;
  end if;
  return new;
end;
$$;

-- The insert policy only ever allowed someone to create a loan for
-- themselves, so an admin recording a borrowing had to go through
-- record_loan_for_member(). Allowing it directly keeps the rule in one
-- place and matches how contributions already work.
drop policy if exists loans_insert_member on public.loans;

create policy loans_insert_member on public.loans
  for insert
  with check (
    public.is_chama_member(chama_id)
    and public.is_chama_active(chama_id)
    and (
      -- An admin records a borrowing for anyone in the chama.
      public.is_chama_admin(chama_id)
      -- Anyone else may only ask for one, for themselves.
      or (
        status = 'pending'
        and member_id in (
          select cm.id from public.chama_members cm
          where cm.chama_id = loans.chama_id and cm.user_id = auth.uid()
        )
      )
    )
  );

-- --------------------------------------------------- 2. interest period

alter table public.loans
  add column if not exists interest_period text not null default 'one_off';

alter table public.loans
  drop constraint if exists loans_interest_period_check;

alter table public.loans
  add constraint loans_interest_period_check
  check (interest_period in ('one_off', 'per_month', 'per_annum'));

-- How long a loan runs, in started months, from the day it was issued to
-- the day it falls due. A chama charging "5% a month" means every month
-- begun, so a 35-day loan costs two months — rounding up is the
-- behaviour people expect and the one they would otherwise argue about.
-- With no due date there is nothing to measure, so it is one period.
create or replace function public.loan_term_months(
  p_issued timestamptz,
  p_due date
)
returns numeric
language sql
immutable
as $$
  select case
    when p_issued is null or p_due is null then 1
    else greatest(1, ceil(greatest(p_due - p_issued::date, 0) / 30.0))
  end;
$$;

-- What a loan costs to repay, given its rate, period and term. Simple
-- interest throughout: chamas do not compound, and a member who cannot
-- reproduce the figure on paper will not trust it.
create or replace function public.loan_total_due(
  p_principal numeric,
  p_rate numeric,
  p_period text,
  p_issued timestamptz,
  p_due date
)
returns numeric
language sql
immutable
as $$
  select round(
    p_principal * (
      1 + coalesce(p_rate, 0) / 100 * case coalesce(p_period, 'one_off')
        when 'per_month'  then public.loan_term_months(p_issued, p_due)
        when 'per_annum'  then public.loan_term_months(p_issued, p_due) / 12.0
        else 1
      end
    ),
    2
  );
$$;

create or replace function public.handle_loan_activation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'active' and old.status is distinct from 'active' then
    new.issued_at := coalesce(new.issued_at, now());
    new.total_due := public.loan_total_due(
      new.principal, new.interest_rate, new.interest_period,
      new.issued_at, new.due_date);

    insert into public.transactions
      (chama_id, member_id, type, amount, reference_id, occurred_at)
    values
      (new.chama_id, new.member_id, 'loan_disbursement', new.principal, new.id,
       new.issued_at);
  end if;
  return new;
end;
$$;

-- ------------------------------------------- the two ways a loan starts

drop function if exists public.record_loan_for_member(uuid, uuid, numeric, numeric, text, date);

create function public.record_loan_for_member(
  p_chama_id uuid,
  p_member_id uuid,
  p_principal numeric,
  p_interest_rate numeric default 0,
  p_purpose text default null,
  p_due_date date default null,
  p_interest_period text default 'one_off'
)
returns uuid
language plpgsql
security definer
set search_path = public
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

  if not exists (
    select 1 from public.chama_members m
    where m.id = p_member_id and m.chama_id = p_chama_id and m.status = 'active'
  ) then
    raise exception 'That member is not in this chama';
  end if;

  -- A rate charged per month or per year is meaningless without knowing
  -- how long the loan runs.
  if coalesce(p_interest_period, 'one_off') <> 'one_off'
     and coalesce(p_interest_rate, 0) > 0
     and p_due_date is null then
    raise exception 'A loan charged per month or per year needs a due date';
  end if;

  insert into public.loans
    (chama_id, member_id, principal, interest_rate, interest_period,
     purpose, due_date, status, approved_by, issued_at)
  values
    (p_chama_id, p_member_id, p_principal, coalesce(p_interest_rate, 0),
     coalesce(p_interest_period, 'one_off'),
     p_purpose, p_due_date, 'pending', auth.uid(), now())
  returning id into v_loan_id;

  update public.loans set status = 'active' where id = v_loan_id;

  return v_loan_id;
end;
$$;

grant execute on function public.record_loan_for_member(uuid, uuid, numeric, numeric, text, date, text)
  to authenticated;

drop function if exists public.approve_loan(uuid, numeric, date);

create function public.approve_loan(
  p_loan_id uuid,
  p_interest_rate numeric default 0,
  p_due_date date default null,
  p_interest_period text default 'one_off'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans%rowtype;
begin
  select * into v_loan from public.loans where id = p_loan_id;

  if not found then
    raise exception 'That loan request no longer exists';
  end if;

  if not public.is_chama_admin(v_loan.chama_id) then
    raise exception 'Only the chairperson or treasurer can approve a loan';
  end if;

  if v_loan.status not in ('pending', 'rejected') then
    raise exception 'That loan has already been decided';
  end if;

  if coalesce(p_interest_period, 'one_off') <> 'one_off'
     and coalesce(p_interest_rate, 0) > 0
     and p_due_date is null then
    raise exception 'A loan charged per month or per year needs a due date';
  end if;

  update public.loans
     set status = 'active',
         interest_rate = coalesce(p_interest_rate, 0),
         interest_period = coalesce(p_interest_period, 'one_off'),
         due_date = p_due_date,
         approved_by = auth.uid(),
         decided_by = auth.uid(),
         decided_at = now(),
         rejection_reason = null
   where id = p_loan_id;
end;
$$;

grant execute on function public.approve_loan(uuid, numeric, date, text) to authenticated;

-- ------------------------------------------------ 3. interest as income

-- Interest is the chama's income from lending its own money out, and it
-- was counted nowhere: the fund appeared to be worth exactly what people
-- had put into it. Earned is interest on loans already repaid — money the
-- chama is holding. Expected is interest on loans still running, which it
-- is owed but does not have, and the two must never be added together
-- silently.
drop function if exists public.chama_totals(uuid);

create function public.chama_totals(p_chama_id uuid)
returns table (
  total_contributions numeric,
  member_count integer,
  total_loans_disbursed numeric,
  total_outstanding numeric,
  active_loan_count integer,
  interest_earned numeric,
  interest_expected numeric
)
language plpgsql
stable
security definer
set search_path = public
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
     where l.chama_id = p_chama_id and l.status = 'active'),
    coalesce((select sum(greatest(l.total_due - l.principal, 0)) from public.loans l
              where l.chama_id = p_chama_id and l.status = 'repaid'), 0),
    coalesce((select sum(greatest(l.total_due - l.principal, 0)) from public.loans l
              where l.chama_id = p_chama_id and l.status = 'active'), 0);
end;
$$;

grant execute on function public.chama_totals(uuid) to authenticated;

-- Existing loans predate the period column and were all flat one-offs,
-- which the default already records. Their stored total_due stays as it
-- was computed; recalculating would move figures members have been shown.
-- An admin recording a borrowing on a member's behalf does not need to be
-- told about their own entry. Contributions already work this way; loan
-- requests did not, so a chairperson writing up the year's lending got a
-- notification for each one.
create or replace function public.handle_loan_request_notification()
returns trigger
language plpgsql
security definer
set search_path = public
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
    and m.user_id is not null
    and m.user_id is distinct from auth.uid();

  return new;
end;
$$;
