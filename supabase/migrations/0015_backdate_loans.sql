-- Recording a loan that was taken out in the past.
--
-- record_loan_for_member() always stamped the issue date as now(), which
-- was fine while the only use was lending money today. A chairperson
-- writing up a year of back history cannot: the issue date is what the
-- term is measured from, so a 2025 loan recorded as issued today is
-- charged for three months instead of thirteen. On a 20,000 loan at 1% a
-- month that is the difference between 20,600 and 22,600.
--
-- Contributions have had a date of their own since the beginning. Loans
-- now do too.

drop function if exists public.record_loan_for_member(uuid, uuid, numeric, numeric, text, date, text);

create function public.record_loan_for_member(
  p_chama_id uuid,
  p_member_id uuid,
  p_principal numeric,
  p_interest_rate numeric default 0,
  p_purpose text default null,
  p_due_date date default null,
  p_interest_period text default 'one_off',
  p_issued_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan_id uuid;
  v_issued timestamptz;
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

  v_issued := coalesce(p_issued_at, now());

  -- Money cannot have been lent in a future the chama has not reached.
  if v_issued > now() then
    raise exception 'A loan cannot be dated in the future';
  end if;

  -- A rate charged per month or per year is meaningless without knowing
  -- how long the loan runs.
  if coalesce(p_interest_period, 'one_off') <> 'one_off'
     and coalesce(p_interest_rate, 0) > 0
     and p_due_date is null then
    raise exception 'A loan charged per month or per year needs a due date';
  end if;

  if p_due_date is not null and p_due_date < v_issued::date then
    raise exception 'The due date is before the loan was taken out';
  end if;

  insert into public.loans
    (chama_id, member_id, principal, interest_rate, interest_period,
     purpose, due_date, status, approved_by, issued_at)
  values
    (p_chama_id, p_member_id, p_principal, coalesce(p_interest_rate, 0),
     coalesce(p_interest_period, 'one_off'),
     p_purpose, p_due_date, 'pending', auth.uid(), v_issued)
  returning id into v_loan_id;

  -- Activating is what computes total_due and writes the ledger entry,
  -- both of which read issued_at — so it has to be set before this.
  update public.loans set status = 'active' where id = v_loan_id;

  return v_loan_id;
end;
$$;

grant execute on function public.record_loan_for_member(
  uuid, uuid, numeric, numeric, text, date, text, timestamptz) to authenticated;
