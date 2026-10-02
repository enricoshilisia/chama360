-- Taking a member off the active roster, with a reason on the record.
--
-- People die, move away, or leave. Until now the only option was
-- "removed", set with no reason and no author — which reads as expulsion
-- whatever actually happened, and tells a future chairperson nothing. A
-- family chama looking at its own history in ten years should be able to
-- see that someone was archived because they died, not merely that they
-- stopped appearing.
--
-- Archiving moves nobody's money. If the member still holds shares those
-- shares stay in their name until somebody transfers them, which is a
-- separate, deliberate act with its own audit (see 0013).

alter table public.chama_members
  drop constraint if exists chama_members_status_check;

alter table public.chama_members
  add constraint chama_members_status_check
  check (status in ('active', 'pending', 'removed', 'archived'));

alter table public.chama_members
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references public.profiles(id),
  add column if not exists archive_reason text,
  add column if not exists archive_note text,
  -- What they held at the moment they were archived. Kept because a
  -- balance can be transferred away afterwards, and the question "what
  -- did they have when they left" then has no other answer.
  add column if not exists archived_balance numeric(14,2);

alter table public.chama_members
  drop constraint if exists chama_members_archive_reason_check;

alter table public.chama_members
  add constraint chama_members_archive_reason_check
  check (archive_reason is null or archive_reason in
    ('deceased', 'left', 'relocated', 'inactive', 'removed', 'other'));

-- ------------------------------------------------------------- archive

create or replace function public.archive_member(
  p_member_id uuid,
  p_reason text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.chama_members%rowtype;
  v_admins integer;
begin
  select * into v_member from public.chama_members where id = p_member_id;

  if not found then
    raise exception 'That member no longer exists';
  end if;

  if not public.is_chama_admin(v_member.chama_id) then
    raise exception 'Only the chairperson or treasurer can archive a member';
  end if;

  if v_member.status <> 'active' then
    raise exception 'That member is not on the active roster';
  end if;

  if p_reason is null or p_reason not in
     ('deceased', 'left', 'relocated', 'inactive', 'removed', 'other') then
    raise exception 'Choose a reason for archiving this member';
  end if;

  -- "Other" is only useful if it says what the other thing was.
  if p_reason = 'other' and (p_note is null or length(trim(p_note)) = 0) then
    raise exception 'Say what the reason is';
  end if;

  -- A chama with nobody who can run it is a chama nobody can fix.
  select count(*) into v_admins
  from public.chama_members
  where chama_id = v_member.chama_id
    and status = 'active'
    and role in ('chairperson', 'treasurer')
    and id <> p_member_id;

  if v_member.role in ('chairperson', 'treasurer') and v_admins = 0 then
    raise exception 'Make someone else chairperson or treasurer first — this is the only one left';
  end if;

  update public.chama_members
     set status = 'archived',
         archived_at = now(),
         archived_by = auth.uid(),
         archive_reason = p_reason,
         archive_note = nullif(trim(coalesce(p_note, '')), ''),
         archived_balance = balance
   where id = p_member_id;
end;
$$;

grant execute on function public.archive_member(uuid, text, text) to authenticated;

-- Archiving the wrong person is an easy mistake and leaving no way back
-- would make it an expensive one.
create or replace function public.restore_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.chama_members%rowtype;
begin
  select * into v_member from public.chama_members where id = p_member_id;

  if not found then
    raise exception 'That member no longer exists';
  end if;

  if not public.is_chama_admin(v_member.chama_id) then
    raise exception 'Only the chairperson or treasurer can restore a member';
  end if;

  if v_member.status not in ('archived', 'removed') then
    raise exception 'That member is already on the roster';
  end if;

  update public.chama_members
     set status = 'active',
         archived_at = null,
         archived_by = null,
         archive_reason = null,
         archive_note = null,
         archived_balance = null
   where id = p_member_id;
end;
$$;

grant execute on function public.restore_member(uuid) to authenticated;

-- ---------------------------------------------------------- the record

-- Everyone who has left the roster, why, on whose authority, and what
-- they were holding at the time. Admin-only: this is the chama's own
-- administrative history, not something the rest of the roster reads.
create or replace function public.chama_archived_members(p_chama_id uuid)
returns table (
  id uuid,
  display_name text,
  role text,
  status text,
  archived_at timestamptz,
  archive_reason text,
  archive_note text,
  archived_balance numeric,
  balance numeric,
  archived_by_name text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_chama_admin(p_chama_id) then
    raise exception 'Only the chairperson or treasurer can see the archive';
  end if;

  return query
  select
    m.id,
    coalesce(nullif(trim(p.full_name), ''), m.full_name, p.email, 'Member'),
    m.role,
    m.status,
    m.archived_at,
    m.archive_reason,
    m.archive_note,
    m.archived_balance,
    m.balance,
    coalesce(nullif(trim(pb.full_name), ''), pb.email, 'An administrator')
  from public.chama_members m
  left join public.profiles p on p.id = m.user_id
  left join public.profiles pb on pb.id = m.archived_by
  where m.chama_id = p_chama_id
    and m.status in ('archived', 'removed')
  order by m.archived_at desc nulls last,
           coalesce(nullif(trim(p.full_name), ''), m.full_name);
end;
$$;

grant execute on function public.chama_archived_members(uuid) to authenticated;
