-- =====================================================================
-- Daily Report LKA - Target November 2026 (dari "Daftar Target PC & Sales.xlsx")
--   Target Sales per area: unit HP, tipe fokus (= A7 Pro + Reno 16), unit IoT.
--     Target value Sales tidak ada di Excel -> otomatis jumlah target value PC.
--   Target Trainer = jumlah target semua Sales yang dipegang (dihitung otomatis, tidak disimpan).
--   Target PC: value, unit HP, tipe fokus (= A7 Pro + Reno 16), unit IoT.
-- Jalankan SETELAH tahap_6.sql. Aman dijalankan ulang (menimpa target November). Tetap bisa diedit di aplikasi.
-- =====================================================================

-- Target Sales (dicocokkan lewat nama area = SALES REGION)
insert into public.sales_targets (sales_id, bulan, jenis, nilai)
select a.sales_id, date '2026-11-01', j.jenis, j.nilai
  from (values
  ('LAMANDAU', 400, 60, 50),
  ('PKY 1', 515, 115, 40),
  ('SAMPIT KOTA 1', 335, 55, 55),
  ('PANGKALANBUN 2', 205, 40, 30),
  ('PANGKALANBUN 1', 325, 50, 35),
  ('SAMPIT KOTA 2', 365, 55, 40),
  ('KASONGAN', 420, 50, 55),
  ('MUARA TEWEH', 330, 45, 40),
  ('PURUK CAHU', 200, 40, 30),
  ('GUNUNG MAS', 245, 35, 30),
  ('PKY 2', 310, 55, 30)
  ) v(area, unit, fokus, iot)
  join public.areas a on upper(trim(a.nama)) = upper(trim(v.area)) and a.sales_id is not null
 cross join lateral (values ('unit', v.unit), ('fokus', v.fokus), ('iot', v.iot)) j(jenis, nilai)
on conflict (sales_id, bulan, jenis) do update set nilai = excluded.nilai;

-- Target PC (dicocokkan lewat nama PC). Satu perintah tanpa tabel sementara, sekaligus menampilkan hasil.
with v(nama, unit, value, fokus, iot) as (values
  ('RABIATUL ADHAWIAH', 35, 80000000, 5, 3),
  ('M. RAHMANI', 30, 80000000, 7, 3),
  ('DATIK PRIHATIN', 30, 70000000, 5, 3),
  ('SITI MUNASAROH', 30, 70000000, 5, 3),
  ('MUHAMMAD MAHFUZH AMIN', 30, 70000000, 5, 3),
  ('RIKA MARWATI', 30, 70000000, 5, 3),
  ('ELFIANI KHOLISNA SALSABILA', 30, 100000000, 8, 3),
  ('AINUN NISA', 35, 100000000, 5, 3),
  ('NURAHMAN', 30, 70000000, 5, 3),
  ('LUCI LAUZA SAHIRA', 45, 180000000, 8, 3),
  ('FAIS CATHERINE', 30, 70000000, 6, 3),
  ('FREDI LINTANG KUSUMO', 30, 80000000, 6, 3),
  ('NOVIYANA', 35, 140000000, 8, 3),
  ('ARIF ILHAM', 30, 70000000, 5, 3),
  ('AMELIA DEWI NUGRAHANI', 30, 70000000, 5, 3),
  ('AHMAD DAVIN ALGIFARI', 30, 70000000, 5, 3),
  ('HERLINA', 35, 100000000, 5, 3),
  ('NURMAULIDDAH', 30, 100000000, 7, 3),
  ('SELVINA RAHMADANI', 30, 70000000, 8, 3),
  ('AHMAD YANI AKBAR', 35, 100000000, 7, 3),
  ('GITA', 35, 130000000, 8, 3),
  ('LIE ERVENDI', 30, 70000000, 6, 3),
  ('NINDI AYU ASTIRA', 30, 70000000, 7, 3),
  ('KHAIRULLAH AKHMAD', 30, 80000000, 6, 3),
  ('TANZILLA NURDHIA ASRA', 30, 80000000, 9, 3),
  ('AYU PUJI LESTARI', 30, 70000000, 6, 3),
  ('MELISA', 30, 70000000, 6, 3),
  ('AHMAD RIDHA', 30, 80000000, 6, 3),
  ('MUHAMMAD ZAINI', 35, 100000000, 6, 3),
  ('AKHMAD RIFKY MUNADA', 35, 180000000, 12, 3),
  ('RESTU NOVITASARI', 40, 210000000, 13, 3),
  ('TANIYA', 30, 100000000, 11, 3),
  ('AHMAD AZMAN FIKRI', 50, 180000000, 5, 3),
  ('EGY FARADILA', 35, 130000000, 5, 3),
  ('THALHAH', 30, 70000000, 5, 3),
  ('ADELIA SEKAR PERMATA', 30, 70000000, 6, 3),
  ('SHALEHAH', 40, 160000000, 7, 3),
  ('UTIN SONIA FEBRIANTI', 30, 70000000, 6, 3),
  ('RIRIN ARUM KUSUMA', 30, 130000000, 7, 3),
  ('NURSUCI LATIFATU SOLEHAH', 30, 70000000, 6, 3),
  ('AHMAD SYAFIQ', 30, 70000000, 6, 3),
  ('GIRI ADI LASA', 40, 130000000, 7, 3),
  ('ABELIA SAFIRA', 30, 70000000, 6, 3),
  ('SUMARDI', 35, 140000000, 9, 3),
  ('WAHYUDI AL AMIN', 30, 90000000, 9, 3),
  ('DARMAWAN', 35, 130000000, 8, 3),
  ('KHAIRUL', 35, 170000000, 10, 3),
  ('MUHAMMAD SYAUFI', 30, 100000000, 7, 3),
  ('INDRI SULASTRI', 30, 70000000, 6, 3),
  ('HENDRA GUNAWAN', 40, 140000000, 11, 3),
  ('MOZA ANISA SAFITRI', 30, 80000000, 7, 3),
  ('HAIKAL', 35, 130000000, 8, 3),
  ('AGUS SUSILO', 35, 100000000, 9, 3),
  ('SATARIAN', 30, 130000000, 8, 3),
  ('ULFAH', 40, 140000000, 9, 3),
  ('NELA WULANDARI', 30, 80000000, 8, 3),
  ('HADIJAH', 35, 140000000, 9, 3),
  ('MUHAMMAD YUDI', 30, 90000000, 8, 3),
  ('NABILA AI''SA PUTRI', 30, 70000000, 7, 3),
  ('MUFARIKHAH ANGGRAENI', 40, 140000000, 8, 3),
  ('KLINDRI KLARANA', 45, 170000000, 7, 3),
  ('DESTI FITRIYANI', 30, 100000000, 9, 3),
  ('SIBUN', 35, 130000000, 10, 3),
  ('DIAN MARNITA', 30, 140000000, 12, 3),
  ('NADA', 35, 160000000, 13, 3),
  ('MUHAMMAD ILHAM MAHDIAN', 35, 130000000, 11, 3),
  ('NUR RAHMANINGSIH', 35, 130000000, 10, 3),
  ('NURIYAH', 30, 70000000, 9, 3),
  ('DEWI NOR YULIANTI', 45, 170000000, 12, 3),
  ('AYU ANGGRAINI', 35, 160000000, 12, 3),
  ('RINA MARDIANA', 60, 250000000, 16, 3),
  ('ISNA', 60, 250000000, 25, 3),
  ('ZENNY YANI', 30, 70000000, 6, 4),
  ('SALWA SYAKILLA RAMADHANI', 30, 70000000, 5, 4),
  ('MAWADDAH', 35, 130000000, 8, 4),
  ('DZIKRUL HIDAYAH RAMADHANI', 30, 80000000, 8, 4),
  ('ZAINAL ABIDIN', 35, 140000000, 10, 4),
  ('SRI SUCI WATI', 60, 250000000, 11, 4),
  ('M. ILHAM NASIR', 30, 90000000, 9, 4),
  ('NADYA PURNAMA SARI', 35, 160000000, 9, 4),
  ('REZKI EFENDY RAHMAN', 30, 100000000, 9, 4),
  ('YULIANA', 30, 130000000, 8, 4),
  ('DEVI RUSMALA SARI', 45, 210000000, 15, 4),
  ('MUHAMAD AHYAR', 70, 250000000, 11, 4),
  ('SITI AISYAH', 30, 130000000, 11, 4),
  ('SINTA WULANDARI', 45, 170000000, 10, 4),
  ('JULKIFLI', 60, 250000000, 24, 4),
  ('NOOR. M. RIFQAH', 30, 80000000, 6, 5),
  ('JULFIA AYU LESTARI', 45, 180000000, 8, 5),
  ('YENI YUSNIA', 30, 70000000, 5, 5),
  ('MULIANTHI', 40, 160000000, 7, 5),
  ('ROMIYADI', 35, 130000000, 7, 5),
  ('INDRA ARYUDI', 35, 140000000, 9, 5),
  ('TANTRI', 30, 80000000, 10, 5),
  ('WAHYU MUHAMMAD IKROM', 30, 100000000, 9, 5),
  ('MARIAM', 35, 130000000, 10, 5),
  ('UTIN AMELIA PUTRI DEWI', 30, 90000000, 8, 6),
  ('MISNAWATI', 35, 90000000, 6, 6),
  ('JAINI', 45, 170000000, 9, 6),
  ('LIYANTO', 60, 250000000, 16, 6),
  ('NADILA', 60, 250000000, 20, 6),
  ('ALMIRA', 45, 180000000, 8, 10),
  ('BAYU SUSENO', 45, 210000000, 11, 10),
  ('A AN DAENI', 50, 250000000, 11, 10),
  ('ISTIKAMAH', 70, 250000000, 13, 10),
  ('ERA NOVALLISTI', 45, 210000000, 9, 15),
  ('SILVI RESGITA PUTRI RISANTI', 70, 250000000, 9, 15),
  ('SAPITRI', 70, 250000000, 9, 20)
),
masuk as (
  insert into public.pc_targets (pc_id, bulan, jenis, nilai)
  select p.id, date '2026-11-01', j.jenis, j.nilai
    from v
    join public.profiles p on p.role = 'pc' and upper(trim(p.nama)) = upper(trim(v.nama))
   cross join lateral (values ('unit', v.unit), ('value', v.value), ('fokus', v.fokus), ('iot', v.iot)) j(jenis, nilai)
  on conflict (pc_id, bulan, jenis) do update set nilai = excluded.nilai
  returning pc_id
)
select 'Target masuk' as status,
       (select count(distinct sales_id) from public.sales_targets where bulan = date '2026-11-01') as sales,
       (select count(distinct pc_id) from masuk) as pc,
       (select string_agg(v.nama, ', ') from v
         where not exists (select 1 from public.profiles p where p.role = 'pc' and upper(trim(p.nama)) = upper(trim(v.nama)))) as pc_tidak_ketemu;
