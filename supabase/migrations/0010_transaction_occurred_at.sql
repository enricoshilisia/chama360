-- When the money moved, as distinct from when the row was written.
--
-- The ledger only ever had created_at, and every screen showed it. For a
-- contribution recorded the same day that is the same thing, so the bug
-- stayed invisible until a chama imported three years of history in one
-- afternoon and every entry from 2017 onwards displayed as today.
--
-- created_at stays as it is — it is a real fact and the audit trail wants
-- it. occurred_at is the value date, and it is the one people mean when
-- they ask when a contribution was made.

alter table public.transactions
  add column if not exists occurred_at timestamptz;

-- Backfill from whatever the entry points at. Each source already knows
-- its own date; the ledger simply never copied it across.
update public.transactions t
   set occurred_at = c.contribution_date::timestamptz
  from public.contributions c
 where t.reference_id = c.id
   and t.type = 'contribution'
   and t.occurred_at is null;

-- A reversal happened when it was reversed, not when the contribution it
-- cancels was made — that is the whole point of a reversal being its own
-- dated entry rather than an edit.
update public.transactions t
   set occurred_at = coalesce(c.reversed_at, t.created_at)
  from public.contributions c
 where t.reference_id = c.id
   and t.type = 'reversal'
   and t.occurred_at is null;

update public.transactions t
   set occurred_at = coalesce(l.issued_at, l.created_at)
  from public.loans l
 where t.reference_id = l.id
   and t.type = 'loan_disbursement'
   and t.occurred_at is null;

update public.transactions t
   set occurred_at = r.repaid_at
  from public.loan_repayments r
 where t.reference_id = r.id
   and t.type = 'loan_repayment'
   and t.occurred_at is null;

-- Anything else, and anything whose source row has since gone: the write
-- date is the best answer available and is what was being shown anyway.
update public.transactions
   set occurred_at = created_at
 where occurred_at is null;

alter table public.transactions
  alter column occurred_at set default now(),
  alter column occurred_at set not null;

-- Every feed reads a chama's ledger newest-first by value date.
create index if not exists idx_transactions_chama_occurred
  on public.transactions (chama_id, occurred_at desc);

-- --------------------------------------------------- keep it filled in

create or replace function public.handle_new_contribution()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_balance numeric(14,2);
begin
  if new.status = 'completed' then
    update public.chama_members
      set balance = balance + new.amount
      where id = new.member_id
      returning balance into v_new_balance;

    insert into public.transactions
      (chama_id, member_id, type, amount, reference_id, balance_after, occurred_at)
    values
      (new.chama_id, new.member_id, 'contribution', new.amount, new.id,
       v_new_balance, new.contribution_date::timestamptz);
  end if;
  return new;
end;
$$;

create or replace function public.handle_loan_activation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'active' and old.status is distinct from 'active' then
    new.total_due := new.principal + (new.principal * new.interest_rate / 100);
    new.issued_at := coalesce(new.issued_at, now());

    insert into public.transactions
      (chama_id, member_id, type, amount, reference_id, occurred_at)
    values
      (new.chama_id, new.member_id, 'loan_disbursement', new.principal, new.id,
       new.issued_at);
  end if;
  return new;
end;
$$;

create or replace function public.handle_loan_repayment()
returns trigger
language plpgsql
security definer
set search_path = public
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

  insert into public.transactions
    (chama_id, member_id, type, amount, reference_id, occurred_at)
  values
    (v_chama_id, v_member_id, 'loan_repayment', new.amount, new.id, new.repaid_at);

  return new;
end;
$$;

-- The reversal function writes a ledger entry too (see 0008).
create or replace function public.reverse_contribution(
  p_contribution_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contribution public.contributions%rowtype;
  v_new_balance numeric(14,2);
  v_member_user uuid;
  v_chama_name text;
begin
  select * into v_contribution
  from public.contributions
  where id = p_contribution_id;

  if not found then
    raise exception 'That contribution no longer exists';
  end if;

  if not public.is_chama_admin(v_contribution.chama_id) then
    raise exception 'Only the chairperson or treasurer can reverse a contribution';
  end if;

  if v_contribution.status = 'reversed' then
    raise exception 'That contribution has already been reversed';
  end if;

  if v_contribution.status <> 'completed' then
    raise exception 'Only a completed contribution can be reversed';
  end if;

  -- Mandatory, for the same reason a loan rejection needs one: the member
  -- whose record just changed is owed an explanation.
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Give a reason for the reversal';
  end if;

  update public.contributions
     set status = 'reversed',
         reversed_at = now(),
         reversed_by = auth.uid(),
         reversal_reason = trim(p_reason)
   where id = p_contribution_id;

  update public.chama_members
     set balance = balance - v_contribution.amount
   where id = v_contribution.member_id
   returning balance, user_id into v_new_balance, v_member_user;

  -- A reversal is dated when it happens, not when the contribution it
  -- cancels was made: it is its own entry in the ledger, not an edit.
  insert into public.transactions
    (chama_id, member_id, type, amount, reference_id, balance_after, occurred_at)
  values
    (v_contribution.chama_id, v_contribution.member_id, 'reversal',
     -v_contribution.amount, v_contribution.id, v_new_balance, now());

  -- Tell the member, if they have a login of their own. A managed member
  -- has no account to notify; their chairperson is the one holding the
  -- record either way.
  if v_member_user is not null then
    select name into v_chama_name from public.chamas where id = v_contribution.chama_id;

    insert into public.notifications (user_id, chama_id, title, body, link_type, link_id)
    values (
      v_member_user,
      v_contribution.chama_id,
      'A contribution was reversed',
      'Your contribution of ' || to_char(v_contribution.amount, 'FM999,999,999.00') ||
      ' recorded on ' || to_char(v_contribution.contribution_date, 'DD Mon YYYY') ||
      ' in ' || coalesce(v_chama_name, 'your chama') ||
      ' has been reversed. Reason: ' || trim(p_reason),
      'contribution',
      v_contribution.id
    );
  end if;
end;
$$;

