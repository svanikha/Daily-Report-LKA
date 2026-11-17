-- =====================================================================
-- Daily Report LKA - Keluarkan semua OPPO Store dan Erafone (NKA) dari LKA
-- Menghapus PERMANEN toko yang namanya mengandung "OPPO Store" atau "Erafone" (11 toko)
-- beserta PC-nya (12 PC), login PC, dan semua data harian toko/PC itu (jika ada data percobaan).
-- Area, Sales, dan Trainer tidak dihapus.
-- SQL Editor -> New query -> tempel -> Run. Aman dijalankan ulang.
-- =====================================================================

do $$
declare
  t int[];
  p uuid[];
begin
  select coalesce(array_agg(id), '{}') into t from public.stores where nama ilike '%oppo store%' or nama ilike '%erafone%';
  select coalesce(array_agg(id), '{}') into p from public.profiles where role = 'pc' and store_id = any(t);

  -- Data harian PC & toko
  delete from public.sales where store_id = any(t) or pc_id = any(p);
  delete from public.checkins where pc_id = any(p) or store_id = any(t);
  delete from public.leasing_checks where store_id = any(t) or pc_id = any(p);
  delete from public.daily_reports where store_id = any(t) or pc_id = any(p);
  delete from public.pc_day_status where pc_id = any(p);
  delete from public.pc_targets where pc_id = any(p);
  delete from public.store_targets where store_id = any(t);
  delete from public.competitor_sales_detail where store_id = any(t);
  delete from public.competitor_sales where store_id = any(t);
  delete from public.stok_mutasi where store_id = any(t);
  delete from public.stok_update where store_id = any(t);
  delete from public.stok where store_id = any(t);
  delete from public.login_log where profile_id = any(p);

  -- Login PC, akun PC, lalu toko
  delete from auth.users where id in (select auth_uid from public.profiles where id = any(p) and auth_uid is not null);
  delete from public.profiles where id = any(p);
  delete from public.stores where id = any(t);

  raise notice 'Dihapus: % toko, % PC', coalesce(array_length(t, 1), 0), coalesce(array_length(p, 1), 0);
end $$;

select (select count(*) from public.stores) as toko,
       (select count(*) from public.profiles where role = 'pc') as pc,
       (select count(*) from public.stores where nama ilike '%oppo store%' or nama ilike '%erafone%') as sisa_oppo_store_erafone;
