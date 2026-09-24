-- Bulk import of contribution history from a spreadsheet.
--
-- A chama joining the app arrives with years of records in a book. Typing
-- them in one modal at a time is not a realistic ask, so the app exports a
-- workbook with a sheet per member and takes it back filled in. This is
-- the other end of that: one call, one transaction, either the whole file
-- lands or none of it does.

-- --------------------------------------------------- quiet the notifier

-- The per-contribution notification goes to every member of the chama.
-- For a file carrying three years of history across twenty members that
-- is thousands of alerts about contributions everyone already knows
-- about, so the import switches it off for the duration of its own
-- transaction. Nothing else sets this, and set_config(..., true) means it
-- cannot leak past the statement that set it.
create or replace function public.handle_contribution_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if coalesce(current_setting('app.bulk_import', true), '') = 'on' then
    return new;
  end if;

  if new.status = 'completed' then
    select p.full_name into v_name
    from public.chama_members cm join public.profiles p on p.id = cm.user_id
    where cm.id = new.member_id;

    perform public.notify_chama_members(
      new.chama_id,
      'New contribution',
      coalesce(v_name, 'A member') || ' contributed ' || new.amount::text,
      new.recorded_by
    );
  end if;
  return new;
end;
$$;

-- ------------------------------------------------------------- the import

create or replace function public.import_contributions(
  p_chama_id uuid,
  p_rows jsonb
)
returns table (inserted integer, duplicates integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb;
  v_index integer := 0;
  v_member uuid;
  v_amount numeric;
  v_date date;
  v_notes text;
  v_inserted integer := 0;
  v_duplicates integer := 0;
begin
  if not public.is_chama_admin(p_chama_id) then
    raise exception 'Only the chairperson or treasurer can import contributions';
  end if;

  if not public.is_chama_active(p_chama_id) then
    raise exception 'This chama is not active';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Nothing to import';
  end if;

  if jsonb_array_length(p_rows) = 0 then
    return query select 0, 0;
    return;
  end if;

  if jsonb_array_length(p_rows) > 5000 then
    raise exception 'That file has more than 5000 contributions — split it and import in parts';
  end if;

  perform set_config('app.bulk_import', 'on', true);

  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_index := v_index + 1;
    v_member := nullif(v_row->>'member_id', '')::uuid;
    v_amount := nullif(v_row->>'amount', '')::numeric;
    v_date := nullif(v_row->>'date', '')::date;
    v_notes := nullif(trim(coalesce(v_row->>'notes', '')), '');

    -- The client checks all of this too, and says which sheet and row is
    -- at fault. These are the backstop: a bad row aborts the whole
    -- import rather than landing half a file.
    if v_member is null then
      raise exception 'Row % does not say who it belongs to', v_index;
    end if;

    if not exists (
      select 1 from public.chama_members m
      where m.id = v_member and m.chama_id = p_chama_id and m.status = 'active'
    ) then
      raise exception 'Row % refers to someone who is not an active member of this chama', v_index;
    end if;

    if v_amount is null or v_amount <= 0 then
      raise exception 'Row % has no usable amount', v_index;
    end if;

    if v_date is null then
      raise exception 'Row % has no usable date', v_index;
    end if;

    if v_date > current_date then
      raise exception 'Row % is dated in the future', v_index;
    end if;

    -- Re-uploading a sheet after adding a few more lines is how people
    -- actually work, so an identical row is skipped instead of doubling
    -- someone's total. Reported back, so nothing goes missing silently.
    if exists (
      select 1 from public.contributions c
      where c.chama_id = p_chama_id
        and c.member_id = v_member
        and c.contribution_date = v_date
        and c.amount = v_amount
        and c.status = 'completed'
    ) then
      v_duplicates := v_duplicates + 1;
      continue;
    end if;

    insert into public.contributions
      (chama_id, member_id, amount, contribution_date, notes, method, recorded_by)
    values
      (p_chama_id, v_member, v_amount, v_date, v_notes, 'import', auth.uid());

    v_inserted := v_inserted + 1;
  end loop;

  perform set_config('app.bulk_import', 'off', true);

  return query select v_inserted, v_duplicates;
end;
$$;

grant execute on function public.import_contributions(uuid, jsonb) to authenticated;
