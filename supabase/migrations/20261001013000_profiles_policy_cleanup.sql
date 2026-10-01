-- Urbana Café: collapse overlapping profile SELECT policies.
-- profiles_staff_read already includes self-access, so profile_self is redundant.

drop policy if exists profile_self on public.profiles;
