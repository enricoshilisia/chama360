-- What the entry was for, carried on the ledger row itself.
--
-- A contribution has always been able to take a note ("M-pesa", "paid in
-- cash at the December meeting"), and a reversal is required to carry a
-- reason. Neither reached the ledger, so the one place people actually
-- read their history — a member's activity list — showed a bare amount
-- and a date and nothing about what it was.
--
-- Same shape as occurred_at in 0010: the source row already knows this,
-- the ledger simply never copied it across.

alter table public.transactions
  add column if not exists note text;

update public.transactions t
   set note = nullif(trim(c.notes), '')
  from public.contributions c
 where t.reference_id = c.id
   and t.type = 'contribution'
   and t.note is null;

-- A reversal's reason is the most useful note in the whole ledger: it is
-- the explanation for a figure that changed.
update public.transactions t
   set note = nullif(trim(c.reversal_reason), '')
  from public.contributions c
 where t.reference_id = c.id
   and t.type = 'reversal'
   and t.note is null;

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
      (chama_id, member_id, type, amount, reference_id, balance_after, occurred_at, note)
    values
      (new.chama_id, new.member_id, 'contribution', new.amount, new.id,
       v_new_balance, new.contribution_date::timestamptz,
       nullif(trim(coalesce(new.notes, '')), ''));
  end if;
  return new;
end;
$$;

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
    (chama_id, member_id, type, amount, reference_id, balance_after, occurred_at, note)
  values
    (v_contribution.chama_id, v_contribution.member_id, 'reversal',
     -v_contribution.amount, v_contribution.id, v_new_balance, now(), trim(p_reason));

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
