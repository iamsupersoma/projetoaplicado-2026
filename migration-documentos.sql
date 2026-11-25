-- Documentos: notas em texto e imagem, publicadas na lista de links (leitura pública).
-- Requer a função can_write() da migration dos gestores.

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  title text not null default 'Documento sem título',
  content jsonb not null default '[]'::jsonb,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.documents enable row level security;

drop policy if exists documents_public_read on public.documents;
drop policy if exists documents_read on public.documents;
drop policy if exists documents_write on public.documents;
-- qualquer pessoa lê os publicados
create policy documents_public_read on public.documents
  for select to anon, authenticated using (published);
-- gestores (admin, editor, leitor) enxergam também os rascunhos
create policy documents_read on public.documents
  for select to authenticated using (public.my_role() is not null);
-- só admin e editor escrevem
create policy documents_write on public.documents
  for all to authenticated using (public.can_write()) with check (public.can_write());

grant select on public.documents to anon;
grant select, insert, update, delete on public.documents to authenticated;

-- Imagens: leitura pública, envio só para quem pode editar.
insert into storage.buckets (id, name, public)
values ('documentos', 'documentos', true)
on conflict (id) do nothing;

drop policy if exists documentos_public_read on storage.objects;
drop policy if exists documentos_write on storage.objects;
drop policy if exists documentos_update on storage.objects;
drop policy if exists documentos_delete on storage.objects;
create policy documentos_public_read on storage.objects
  for select to public using (bucket_id = 'documentos');
create policy documentos_write on storage.objects
  for insert to authenticated with check (bucket_id = 'documentos' and public.can_write());
create policy documentos_update on storage.objects
  for update to authenticated using (bucket_id = 'documentos' and public.can_write());
create policy documentos_delete on storage.objects
  for delete to authenticated using (bucket_id = 'documentos' and public.can_write());
