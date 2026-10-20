-- Paying a loan off early should cost less.
--
-- Interest was worked out once, at the moment the loan was recorded, from
-- the issue date to the due date, and stored. A member who borrowed in
-- December and cleared it in June still owed twelve months of interest,
-- which is not what 1% a month means and not what anyone agreed to.
--
-- Interest now accrues with time. What is owed on any given day is the
-- principal plus interest for the months that have actually run, and the
-- loan settles the moment repayments cover that. The scheduled figure
-- stays on the loan as what it would cost if carried to term; when a loan
-- is settled early the stored figure is written down to what was really
-- charged, so the chama's books show interest it actually earned rather
-- than interest it hoped for.
--
-- A flat one-off fee is not time-based and does not reduce: that is what
-- choosing "one-off" rather than "per month" means.
--
-- Interest stops at the due date. Carrying a loan past its deadline does
-- not quietly keep adding to it — that is a conversation for the chama to
-- have, not something the books should do by themselves.

-- What a loan costs if settled on [p_as_of].
create or replace function public.loan_accrued_total(
  p_principal numeric,
  p_rate numeric,
  p_period text,
  p_issued timestamptz,
  p_due date,
  p_as_of date default current_date
)
returns numeric
language sql
immutable
as $$
  select round(
    p_principal * (
      1 + coalesce(p_rate, 0) / 100 * case coalesce(p_period, 'one_off')
        -- A flat fee is charged in full the moment the money goes out.
        when 'per_month' then least(
          public.loan_term_months(p_issued, greatest(p_as_of, p_issued::date)),
          public.loan_term_months(p_issued, p_due))
        when 'per_annum' then least(
          public.loan_term_months(p_issued, greatest(p_as_of, p_issued::date)),
          public.loan_term_months(p_issued, p_due)) / 12.0
        else 1
      end
    ),
    2
  );
$$;

-- What it would take to clear a loan today, and what that saves.
create or replace function public.loan_payoff(
  p_loan_id uuid,
  p_as_of date default current_date
)
returns table (
  principal numeric,
  interest_rate numeric,
  interest_period text,
  months_run numeric,
  months_scheduled numeric,
  interest_so_far numeric,
  payable_now numeric,
  amount_repaid numeric,
  settle_today numeric,
  scheduled_total numeric,
  saving numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  l public.loans%rowtype;
  v_accrued numeric;
begin
  select * into l from public.loans where id = p_loan_id;
  if not found then
    raise exception 'That loan no longer exists';
  end if;

  if not public.is_chama_admin(l.chama_id)
     and not exists (
       select 1 from public.chama_members m
       where m.id = l.member_id and m.user_id = auth.uid()
     ) then
    raise exception 'Not allowed to see this loan';
  end if;

  v_accrued := public.loan_accrued_total(
    l.principal, l.interest_rate, l.interest_period, l.issued_at, l.due_date, p_as_of);

  return query select
    l.principal,
    l.interest_rate,
    l.interest_period,
    least(public.loan_term_months(l.issued_at, greatest(p_as_of, l.issued_at::date)),
          public.loan_term_months(l.issued_at, l.due_date)),
    public.loan_term_months(l.issued_at, l.due_date),
    v_accrued - l.principal,
    v_accrued,
    l.amount_repaid,
    greatest(v_accrued - l.amount_repaid, 0),
    l.total_due,
    greatest(l.total_due - v_accrued, 0);
end;
$$;

grant execute on function public.loan_payoff(uuid, date) to authenticated;

-- Every active loan in a chama, with what it would take to clear each
-- one today. One call rather than one per loan.
create or replace function public.chama_loan_payoffs(
  p_chama_id uuid,
  p_as_of date default current_date
)
returns table (
  loan_id uuid,
  member_id uuid,
  member_name text,
  principal numeric,
  interest_rate numeric,
  interest_period text,
  issued_at timestamptz,
  due_date date,
  status text,
  amount_repaid numeric,
  scheduled_total numeric,
  months_run numeric,
  months_scheduled numeric,
  interest_so_far numeric,
  settle_today numeric,
  saving numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
  v_self uuid;
begin
  if not public.is_chama_member(p_chama_id) then
    raise exception 'Not a member of this chama';
  end if;

  v_is_admin := public.is_chama_admin(p_chama_id);
  select m.id into v_self from public.chama_members m
   where m.chama_id = p_chama_id and m.user_id = auth.uid();

  return query
  select
    l.id,
    l.member_id,
    coalesce(nullif(trim(p.full_name), ''), m.full_name, 'Member'),
    l.principal,
    l.interest_rate,
    l.interest_period,
    l.issued_at,
    l.due_date,
    l.status,
    l.amount_repaid,
    l.total_due,
    least(public.loan_term_months(l.issued_at, greatest(p_as_of, l.issued_at::date)),
          public.loan_term_months(l.issued_at, l.due_date)),
    public.loan_term_months(l.issued_at, l.due_date),
    public.loan_accrued_total(l.principal, l.interest_rate, l.interest_period,
                              l.issued_at, l.due_date, p_as_of) - l.principal,
    greatest(public.loan_accrued_total(l.principal, l.interest_rate, l.interest_period,
                                       l.issued_at, l.due_date, p_as_of)
             - l.amount_repaid, 0),
    greatest(l.total_due - public.loan_accrued_total(l.principal, l.interest_rate,
             l.interest_period, l.issued_at, l.due_date, p_as_of), 0)
  from public.loans l
  join public.chama_members m on m.id = l.member_id
  left join public.profiles p on p.id = m.user_id
  where l.chama_id = p_chama_id
    and (v_is_admin or l.member_id = v_self)
  order by
    case l.status when 'active' then 0 when 'pending' then 1 else 2 end,
    l.issued_at desc nulls last;
end;
$$;

grant execute on function public.chama_loan_payoffs(uuid, date) to authenticated;

-- --------------------------------------------------------- settlement

create or replace function public.handle_loan_repayment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  l public.loans%rowtype;
  v_repaid numeric(14,2);
  v_accrued numeric(14,2);
begin
  select * into l from public.loans where id = new.loan_id;

  -- What the loan had actually cost by the day this money came in. A
  -- member clearing in June pays six months of interest, not twelve.
  v_accrued := public.loan_accrued_total(
    l.principal, l.interest_rate, l.interest_period,
    l.issued_at, l.due_date, coalesce(new.repaid_at, now())::date);

  update public.loans
     set amount_repaid = amount_repaid + new.amount
   where id = new.loan_id
   returning amount_repaid into v_repaid;

  if v_repaid >= v_accrued then
    -- Settled. The amount actually charged becomes the loan's total, so
    -- the chama's interest figures show what it earned rather than what
    -- it would have earned had the loan run its course.
    update public.loans
       set status = 'repaid',
           total_due = v_accrued
     where id = new.loan_id;
  end if;

  insert into public.transactions
    (chama_id, member_id, type, amount, reference_id, occurred_at)
  values
    (l.chama_id, l.member_id, 'loan_repayment', new.amount, new.id,
     coalesce(new.repaid_at, now()));

  return new;
end;
$$;
