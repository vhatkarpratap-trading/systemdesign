-- 1. Create the bucket (You usually do this in Dashboard, but this SQL works if extensions enabled)
insert into storage.buckets (id, name, public)
values ('blueprints', 'blueprints', true)
on conflict (id) do nothing;

-- 2. Enable RLS
create policy "Public Access"
  on storage.objects for select
  using ( bucket_id = 'blueprints' );

create policy "Authenticated Users can upload"
  on storage.objects for insert
  with check ( bucket_id = 'blueprints' and auth.role() = 'authenticated' );

create policy "Users can update own files"
  on storage.objects for update
  using ( bucket_id = 'blueprints' and auth.uid() = owner );

-- 3. Update designs table
alter table public.designs 
add column if not exists blueprint_path text;
