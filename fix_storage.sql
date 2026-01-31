-- FINAL FIX: Syncs Database Schema & Permissions

-- 1. Add ALL potentially missing columns from recent code updates
alter table public.designs 
add column if not exists blueprint_path text,
add column if not exists thumbnail_url text,
add column if not exists updated_at timestamp with time zone default timezone('utc'::text, now()),
add column if not exists is_public boolean default true;

-- 2. Drop Old Policies (Prevent conflicts)
drop policy if exists "Authenticated Uploads" on storage.objects;
drop policy if exists "Public View" on storage.objects;
drop policy if exists "Authenticated Users can upload" on storage.objects;

-- 3. Create Fresh Storage Policies
create policy "Authenticated Uploads"
  on storage.objects for insert
  to authenticated
  with check ( bucket_id = 'blueprints' );

create policy "Public View"
  on storage.objects for select
  to public
  using ( bucket_id = 'blueprints' );

-- 4. Refresh Cache
notify pgrst, 'reload config';
