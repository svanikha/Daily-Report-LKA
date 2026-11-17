-- =====================================================================
-- Daily Report LKA - Tandai NOSELL 1-17 November 2026
--   Untuk setiap PC aktif: tanggal 1-17 November tanpa penjualan (HP maupun IoT) ditandai NOSELL.
--   Dilewati: tanggal offday / izin / sakit PC itu, dan tanggal yang sudah ditandai.
--   PC bisa mengubah sendiri: menambah penjualan di tanggal itu otomatis menghapus tanda NOSELL.
-- Jalankan SETELAH penjualan_2026_11_01_17.sql. Aman dijalankan ulang.
-- =====================================================================
with masuk as (
  insert into public.checkins (pc_id, tanggal, modul, store_id)
  select p.id, g.d::date, 'penjualan', p.store_id
    from public.profiles p
   cross join generate_series(date '2026-11-01', date '2026-11-17', interval '1 day') g(d)
   where p.role = 'pc' and p.aktif and p.store_id is not null
     and not exists (select 1 from public.sales s where s.pc_id = p.id and s.tanggal = g.d::date)
     and not exists (select 1 from public.pc_day_status ds where ds.pc_id = p.id and ds.tanggal = g.d::date)
  on conflict (pc_id, tanggal, modul) do nothing
  returning pc_id
)
select 'NOSELL ditandai' as status,
       (select count(*) from masuk) as hari_nosell,
       (select count(distinct pc_id) from masuk) as pc;
