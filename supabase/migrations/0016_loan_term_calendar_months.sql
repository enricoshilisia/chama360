-- A year is twelve months, not thirteen.
--
-- loan_term_months() measured the term as ceil(days / 30). That quietly
-- treats a month as 30 days, so a full year — 365 days — came out as
-- 12.17 and rounded up to 13. Every loan running a year was charged an
-- extra month of interest: at 1% a month on 20,000 that is 200 shillings
-- a borrower does not owe, and it got worse the longer the loan ran.
--
-- The intent was right and stays: a month begun is a month charged. The
-- measurement was wrong. Counting calendar months and adding one only
-- when there are days left over gives what anyone would get counting on
-- a calendar: 26 Dec to 26 Dec is twelve, 26 Dec to 27 Dec is thirteen.

create or replace function public.loan_term_months(
  p_issued timestamptz,
  p_due date
)
returns numeric
language plpgsql
immutable
as $$
declare
  v_gap interval;
  v_months integer;
  v_days integer;
begin
  if p_issued is null or p_due is null then
    return 1;
  end if;

  if p_due <= p_issued::date then
    return 1;
  end if;

  v_gap := age(p_due, p_issued::date);
  v_months := extract(year from v_gap)::integer * 12
            + extract(month from v_gap)::integer;
  v_days := extract(day from v_gap)::integer;

  -- Complete months, plus the one that has been started.
  return greatest(1, v_months + case when v_days > 0 then 1 else 0 end);
end;
$$;

-- ------------------------------------------------- put the figures right

-- The nine loans recorded against 2025 were all computed with the old
-- formula and are each a month over. Nothing has been repaid against any
-- of them, so recomputing moves no money that has actually changed hands;
-- it only corrects what is owed. Loans with repayments against them are
-- deliberately left alone — those figures have been acted on, and
-- changing them silently would be worse than the error.
update public.loans l
   set total_due = public.loan_total_due(
         l.principal, l.interest_rate, l.interest_period, l.issued_at, l.due_date)
 where l.status = 'active'
   and l.amount_repaid = 0
   and l.total_due is distinct from public.loan_total_due(
         l.principal, l.interest_rate, l.interest_period, l.issued_at, l.due_date);
