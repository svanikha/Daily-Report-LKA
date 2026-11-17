-- =====================================================================
-- Daily Report LKA - Data awal (dari Daftar NAMA APK LKA.xlsx, 17 Nov 2026)
-- 4 Trainer, 11 Sales, 11 area, 95 toko, 113 PC.
-- Jalankan SETELAH schema.sql: SQL Editor -> New query -> tempel -> Run. Aman dijalankan ulang.
-- Catatan: awalan "ID-SMQ-SMQ-" dibuang dari nama toko. Toko MULIANA PONSEL (PC Mariam,
-- Sales Heri) dimasukkan ke area PKY 1 milik Heri; bisa dipindah MT lewat menu Toko.
-- Data berikutnya ditambah lewat aplikasi (menu Kelola).
-- =====================================================================

-- 0. NAMA MANAJER TRAINER
update public.profiles set nama = 'AKHMAD SAIFUDDIN' where email = 'mt@dailyreportlka.app';

-- 1. TRAINER
insert into public.profiles (nama, role, email)
select v.nama, 'trainer', v.email from (values
  ('BRANDON CAHYADITA', 'trainer.brandon.cahyadita@dailyreportlka.app'),
  ('ELSA PERMATA SARI', 'trainer.elsa.permata.sari@dailyreportlka.app'),
  ('ISTIHANAH', 'trainer.istihanah@dailyreportlka.app'),
  ('RONNY CHANDRA', 'trainer.ronny.chandra@dailyreportlka.app')
) v(nama, email)
on conflict (email) do update set nama = excluded.nama, aktif = true;

-- 2. SALES dan Trainer yang memegangnya
insert into public.profiles (nama, role, email)
select v.nama, 'sales', v.email from (values
  ('ALWISIUS JATI KURNIAWAN', 'sales.alwisius.jati.kurniawan@dailyreportlka.app'),
  ('HERI SUPRATMAN', 'sales.heri.supratman@dailyreportlka.app'),
  ('INTAN PUTIKA SARI', 'sales.intan.putika.sari@dailyreportlka.app'),
  ('M. KASMIRI', 'sales.m.kasmiri@dailyreportlka.app'),
  ('MUHAMMAD FAHRUR ROZI', 'sales.muhammad.fahrur.rozi@dailyreportlka.app'),
  ('MUHAMMAD HENDY GUNAWAN', 'sales.muhammad.hendy.gunawan@dailyreportlka.app'),
  ('RISHAL ASLANTIANTO', 'sales.rishal.aslantianto@dailyreportlka.app'),
  ('SRIWULANDARI', 'sales.sriwulandari@dailyreportlka.app'),
  ('WIGA BINTANG PRATAMA', 'sales.wiga.bintang.pratama@dailyreportlka.app'),
  ('YANAH', 'sales.yanah@dailyreportlka.app'),
  ('YUNANDES GUNTUR', 'sales.yunandes.guntur@dailyreportlka.app')
) v(nama, email)
on conflict (email) do update set nama = excluded.nama, aktif = true;

insert into public.trainer_sales (sales_id, trainer_id)
select s.id, t.id from (values
  ('sales.alwisius.jati.kurniawan@dailyreportlka.app', 'trainer.istihanah@dailyreportlka.app'),
  ('sales.heri.supratman@dailyreportlka.app', 'trainer.istihanah@dailyreportlka.app'),
  ('sales.intan.putika.sari@dailyreportlka.app', 'trainer.ronny.chandra@dailyreportlka.app'),
  ('sales.m.kasmiri@dailyreportlka.app', 'trainer.brandon.cahyadita@dailyreportlka.app'),
  ('sales.muhammad.fahrur.rozi@dailyreportlka.app', 'trainer.ronny.chandra@dailyreportlka.app'),
  ('sales.muhammad.hendy.gunawan@dailyreportlka.app', 'trainer.elsa.permata.sari@dailyreportlka.app'),
  ('sales.rishal.aslantianto@dailyreportlka.app', 'trainer.elsa.permata.sari@dailyreportlka.app'),
  ('sales.sriwulandari@dailyreportlka.app', 'trainer.ronny.chandra@dailyreportlka.app'),
  ('sales.wiga.bintang.pratama@dailyreportlka.app', 'trainer.brandon.cahyadita@dailyreportlka.app'),
  ('sales.yanah@dailyreportlka.app', 'trainer.elsa.permata.sari@dailyreportlka.app'),
  ('sales.yunandes.guntur@dailyreportlka.app', 'trainer.istihanah@dailyreportlka.app')
) v(sales, trainer)
join public.profiles s on s.email = v.sales
join public.profiles t on t.email = v.trainer
on conflict (sales_id) do update set trainer_id = excluded.trainer_id;

-- Aturan KPI awal untuk setiap Trainer (dilewati jika sudah ada)
select public.kpi_awal(id, public.today_wib()) from public.profiles where role = 'trainer';

-- 3. AREA dan Sales pemiliknya (area baru otomatis mendapat list produk HP & IoT awal)
insert into public.areas (nama, sales_id)
select v.nama, s.id from (values
  ('GUNUNG MAS', 'sales.intan.putika.sari@dailyreportlka.app'),
  ('KASONGAN', 'sales.yunandes.guntur@dailyreportlka.app'),
  ('LAMANDAU', 'sales.rishal.aslantianto@dailyreportlka.app'),
  ('MUARA TEWEH', 'sales.muhammad.fahrur.rozi@dailyreportlka.app'),
  ('PANGKALANBUN 1', 'sales.muhammad.hendy.gunawan@dailyreportlka.app'),
  ('PANGKALANBUN 2', 'sales.yanah@dailyreportlka.app'),
  ('PKY 1', 'sales.heri.supratman@dailyreportlka.app'),
  ('PKY 2', 'sales.alwisius.jati.kurniawan@dailyreportlka.app'),
  ('PURUK CAHU', 'sales.sriwulandari@dailyreportlka.app'),
  ('SAMPIT KOTA 1', 'sales.m.kasmiri@dailyreportlka.app'),
  ('SAMPIT KOTA 2', 'sales.wiga.bintang.pratama@dailyreportlka.app')
) v(nama, sales)
join public.profiles s on s.email = v.sales
on conflict (nama) do update set sales_id = excluded.sales_id;

-- 4. TOKO
insert into public.stores (nama, area_id)
select v.nama, a.id from (values
  ('AIDY PONSEL', 'GUNUNG MAS'),
  ('EHEN PONSEL', 'GUNUNG MAS'),
  ('ESA PONSEL', 'GUNUNG MAS'),
  ('RAHMAT COMPUTER', 'GUNUNG MAS'),
  ('RUNGAN PONSEL', 'GUNUNG MAS'),
  ('ZEN PONSEL_K.KURUN', 'GUNUNG MAS'),
  ('AL-WAFA CELLULAR', 'KASONGAN'),
  ('BERKAT USAHA', 'KASONGAN'),
  ('GRAHA FITRAH CELL', 'KASONGAN'),
  ('JONI PONSEL', 'KASONGAN'),
  ('JONI PONSEL 2', 'KASONGAN'),
  ('JONI PONSEL 3', 'KASONGAN'),
  ('ROBY CELL', 'KASONGAN'),
  ('AVILLA PHONE', 'LAMANDAU'),
  ('BINTANG CELL', 'LAMANDAU'),
  ('DONATUS', 'LAMANDAU'),
  ('FARSHAD CELL', 'LAMANDAU'),
  ('FLOREN CELL', 'LAMANDAU'),
  ('JASA BERSAMA PONSEL DESPOT', 'LAMANDAU'),
  ('NAYA CELL LAMANDAU', 'LAMANDAU'),
  ('PELANGI PONSEL LAMANDAU', 'LAMANDAU'),
  ('SAUDI PONSEL', 'LAMANDAU'),
  ('SMILE CELL', 'LAMANDAU'),
  ('STAR PHONE 3', 'LAMANDAU'),
  ('STAR SELINDO', 'LAMANDAU'),
  ('SUPER CELL_DESPOT', 'LAMANDAU'),
  ('SUPER CELL_LAMANDAU', 'LAMANDAU'),
  ('YUNI PONSEL', 'LAMANDAU'),
  ('CERIA PONSEL TIMPAH', 'MUARA TEWEH'),
  ('CV SURYA INDAH', 'MUARA TEWEH'),
  ('DHONAL PONSEL', 'MUARA TEWEH'),
  ('HAPIDZ PONSEL', 'MUARA TEWEH'),
  ('HUMAIRA CELL', 'MUARA TEWEH'),
  ('IKA PONSEL', 'MUARA TEWEH'),
  ('KARYA BARU', 'MUARA TEWEH'),
  ('MITRA LL', 'MUARA TEWEH'),
  ('RANDE PONSEL', 'MUARA TEWEH'),
  ('RIFA I PONSEL', 'MUARA TEWEH'),
  ('ULIS PONSEL', 'MUARA TEWEH'),
  ('CHIPTA CELL', 'PANGKALANBUN 1'),
  ('HERMAN CRISTIAN', 'PANGKALANBUN 1'),
  ('HERMAN CRISTIAN-EVENT', 'PANGKALANBUN 1'),
  ('METRO PONSEL', 'PANGKALANBUN 1'),
  ('SUKSES MAKMUR. CV', 'PANGKALANBUN 1'),
  ('ZONA CELL P.BUN', 'PANGKALANBUN 1'),
  ('BORNEO MULTI JAYA. CV', 'PANGKALANBUN 2'),
  ('ERAFONE PANGKALANBUN 2', 'PANGKALANBUN 2'),
  ('GLOBAL TOP RETALINDO. CV', 'PANGKALANBUN 2'),
  ('OPPO Store - Pangkalan Bun', 'PANGKALANBUN 2'),
  ('PRIMA PONSEL', 'PANGKALANBUN 2'),
  ('ALFI MITRA TEKNOLOGI. CV', 'PKY 1'),
  ('BETANG CELLULAR', 'PKY 1'),
  ('BUDI MKIOS PONSEL', 'PKY 1'),
  ('CV. NIKKO BERJAYA', 'PKY 1'),
  ('GO PHONE PALANGKARAYA', 'PKY 1'),
  ('MULIANA PONSEL', 'PKY 1'),
  ('Oppo Store - Duta Mall Palangkaraya', 'PKY 1'),
  ('Oppo Store - Palangkaraya', 'PKY 1'),
  ('PT. MEDIA GRUP INTERNASIONAL', 'PKY 1'),
  ('PT. SINAR JAYA SELULAR KAPUAS', 'PKY 1'),
  ('SINAR MAS ABADI . CV', 'PKY 1'),
  ('SUMBER JAYA', 'PKY 1'),
  ('CV. IP PKY PONSEL', 'PKY 2'),
  ('EGA CELL', 'PKY 2'),
  ('ERAFONE DUTA MALL PKY', 'PKY 2'),
  ('ERAFONE P.RAYA 03', 'PKY 2'),
  ('ERAFONE PKY 1', 'PKY 2'),
  ('ERAFONE PKY 2', 'PKY 2'),
  ('H&D', 'PKY 2'),
  ('HAFIZ CELL', 'PKY 2'),
  ('MITRA AGRA KOMUNIKA', 'PKY 2'),
  ('RIZKY PONSEL', 'PKY 2'),
  ('AFE CELLULAR', 'PURUK CAHU'),
  ('ALEK CELL', 'PURUK CAHU'),
  ('ILHAM CELL', 'PURUK CAHU'),
  ('PG STORE', 'PURUK CAHU'),
  ('RAMA PONSEL', 'PURUK CAHU'),
  ('89 PONSEL', 'SAMPIT KOTA 1'),
  ('CENTRAL HAPE PARENGGEAN', 'SAMPIT KOTA 1'),
  ('CV. TELU SEDULUR MARDIKA', 'SAMPIT KOTA 1'),
  ('NAZWA PONSEL', 'SAMPIT KOTA 1'),
  ('PT. SINAR JAYA SELULAR SPT', 'SAMPIT KOTA 1'),
  ('RAHMAN PONSEL', 'SAMPIT KOTA 1'),
  ('RPDHS PONSEL', 'SAMPIT KOTA 1'),
  ('SMART CELL', 'SAMPIT KOTA 1'),
  ('88 PONSEL', 'SAMPIT KOTA 2'),
  ('BIMA PONSEL', 'SAMPIT KOTA 2'),
  ('CV. BERKAT ANUGERAH SOLUSINDO', 'SAMPIT KOTA 2'),
  ('DUNIA ELEKTRONIK', 'SAMPIT KOTA 2'),
  ('ERAFONE SPT', 'SAMPIT KOTA 2'),
  ('ERAFONE SPT 02', 'SAMPIT KOTA 2'),
  ('OPPO Store - Sampit', 'SAMPIT KOTA 2'),
  ('PELANGI SELULER CV', 'SAMPIT KOTA 2'),
  ('STAR PHONE', 'SAMPIT KOTA 2'),
  ('TABRIIZ CELL', 'SAMPIT KOTA 2')
) v(nama, area)
join public.areas a on a.nama = v.area
on conflict (area_id, nama) do nothing;

-- 5. PC (satu toko boleh lebih dari satu PC)
insert into public.profiles (nama, role, store_id, email)
select v.nama, 'pc', s.id, v.email from (values
  ('AHMAD SYAFIQ', 'pc.ahmad.syafiq@dailyreportlka.app', 'ERAFONE PKY 2', 'PKY 2'),
  ('MUHAMMAD SYAUFI', 'pc.muhammad.syaufi@dailyreportlka.app', 'ERAFONE P.RAYA 03', 'PKY 2'),
  ('NURSUCI LATIFATU SOLEHAH', 'pc.nursuci.latifatu.solehah@dailyreportlka.app', 'ERAFONE DUTA MALL PKY', 'PKY 2'),
  ('WAHYU MUHAMMAD IKROM', 'pc.wahyu.muhammad.ikrom@dailyreportlka.app', 'CV. IP PKY PONSEL', 'PKY 2'),
  ('NOVIYANA', 'pc.noviyana@dailyreportlka.app', 'RIZKY PONSEL', 'PKY 2'),
  ('ROMIYADI', 'pc.romiyadi@dailyreportlka.app', 'MITRA AGRA KOMUNIKA', 'PKY 2'),
  ('HADIJAH', 'pc.hadijah@dailyreportlka.app', 'HAFIZ CELL', 'PKY 2'),
  ('ALMIRA', 'pc.almira@dailyreportlka.app', 'H&D', 'PKY 2'),
  ('INDRA ARYUDI', 'pc.indra.aryudi@dailyreportlka.app', 'ERAFONE PKY 1', 'PKY 2'),
  ('GIRI ADI LASA', 'pc.giri.adi.lasa@dailyreportlka.app', 'EGA CELL', 'PKY 2'),
  ('AYU PUJI LESTARI', 'pc.ayu.puji.lestari@dailyreportlka.app', 'PT. MEDIA GRUP INTERNASIONAL', 'PKY 1'),
  ('TANIYA', 'pc.taniya@dailyreportlka.app', 'BUDI MKIOS PONSEL', 'PKY 1'),
  ('M. RAHMANI', 'pc.m.rahmani@dailyreportlka.app', 'SUMBER JAYA', 'PKY 1'),
  ('NADA', 'pc.nada@dailyreportlka.app', 'SINAR MAS ABADI . CV', 'PKY 1'),
  ('AYU ANGGRAINI', 'pc.ayu.anggraini@dailyreportlka.app', 'SINAR MAS ABADI . CV', 'PKY 1'),
  ('DIAN MARNITA', 'pc.dian.marnita@dailyreportlka.app', 'PT. MEDIA GRUP INTERNASIONAL', 'PKY 1'),
  ('YULIANA', 'pc.yuliana@dailyreportlka.app', 'GO PHONE PALANGKARAYA', 'PKY 1'),
  ('REZKI EFENDY RAHMAN', 'pc.rezki.efendy.rahman@dailyreportlka.app', 'CV. NIKKO BERJAYA', 'PKY 1'),
  ('KHAIRUL', 'pc.khairul@dailyreportlka.app', 'BETANG CELLULAR', 'PKY 1'),
  ('MUHAMAD AHYAR', 'pc.muhamad.ahyar@dailyreportlka.app', 'BETANG CELLULAR', 'PKY 1'),
  ('SIBUN', 'pc.sibun@dailyreportlka.app', 'ALFI MITRA TEKNOLOGI. CV', 'PKY 1'),
  ('AKHMAD RIFKY MUNADA', 'pc.akhmad.rifky.munada@dailyreportlka.app', 'PT. SINAR JAYA SELULAR KAPUAS', 'PKY 1'),
  ('RESTU NOVITASARI', 'pc.restu.novitasari@dailyreportlka.app', 'PT. SINAR JAYA SELULAR KAPUAS', 'PKY 1'),
  ('RIZKI PUJA AGUSTIN', 'pc.rizki.puja.agustin@dailyreportlka.app', 'Oppo Store - Palangkaraya', 'PKY 1'),
  ('R. MAWAR DANIATY', 'pc.r.mawar.daniaty@dailyreportlka.app', 'Oppo Store - Duta Mall Palangkaraya', 'PKY 1'),
  ('ROY JHOEDY KUSUMA', 'pc.roy.jhoedy.kusuma@dailyreportlka.app', 'Oppo Store - Duta Mall Palangkaraya', 'PKY 1'),
  ('MARIAM', 'pc.mariam@dailyreportlka.app', 'MULIANA PONSEL', 'PKY 1'),
  ('MAWADDAH', 'pc.mawaddah@dailyreportlka.app', 'ZEN PONSEL_K.KURUN', 'GUNUNG MAS'),
  ('JAINI', 'pc.jaini@dailyreportlka.app', 'ZEN PONSEL_K.KURUN', 'GUNUNG MAS'),
  ('HAIKAL', 'pc.haikal@dailyreportlka.app', 'RUNGAN PONSEL', 'GUNUNG MAS'),
  ('SRI SUCI WATI', 'pc.sri.suci.wati@dailyreportlka.app', 'RAHMAT COMPUTER', 'GUNUNG MAS'),
  ('TANTRI', 'pc.tantri@dailyreportlka.app', 'ESA PONSEL', 'GUNUNG MAS'),
  ('NOOR. M. RIFQAH', 'pc.noor.m.rifqah@dailyreportlka.app', 'EHEN PONSEL', 'GUNUNG MAS'),
  ('RABIATUL ADHAWIAH', 'pc.rabiatul.adhawiah@dailyreportlka.app', 'AIDY PONSEL', 'GUNUNG MAS'),
  ('ISNA', 'pc.isna@dailyreportlka.app', 'PT. SINAR JAYA SELULAR SPT', 'SAMPIT KOTA 1'),
  ('HENDRA GUNAWAN', 'pc.hendra.gunawan@dailyreportlka.app', '89 PONSEL', 'SAMPIT KOTA 1'),
  ('ZAINAL ABIDIN', 'pc.zainal.abidin@dailyreportlka.app', 'CV. TELU SEDULUR MARDIKA', 'SAMPIT KOTA 1'),
  ('MUHAMMAD ILHAM MAHDIAN', 'pc.muhammad.ilham.mahdian@dailyreportlka.app', 'PT. SINAR JAYA SELULAR SPT', 'SAMPIT KOTA 1'),
  ('ABELIA SAFIRA', 'pc.abelia.safira@dailyreportlka.app', 'RPDHS PONSEL', 'SAMPIT KOTA 1'),
  ('SITI AISYAH', 'pc.siti.aisyah@dailyreportlka.app', 'PT. SINAR JAYA SELULAR SPT', 'SAMPIT KOTA 1'),
  ('INDRI SULASTRI', 'pc.indri.sulastri@dailyreportlka.app', 'SMART CELL', 'SAMPIT KOTA 1'),
  ('MISNAWATI', 'pc.misnawati@dailyreportlka.app', 'RAHMAN PONSEL', 'SAMPIT KOTA 1'),
  ('ARIF ILHAM', 'pc.arif.ilham@dailyreportlka.app', 'PT. SINAR JAYA SELULAR SPT', 'SAMPIT KOTA 1'),
  ('YENI YUSNIA', 'pc.yeni.yusnia@dailyreportlka.app', 'NAZWA PONSEL', 'SAMPIT KOTA 1'),
  ('AMELIA DEWI NUGRAHANI', 'pc.amelia.dewi.nugrahani@dailyreportlka.app', 'CENTRAL HAPE PARENGGEAN', 'SAMPIT KOTA 1'),
  ('SHALEHAH', 'pc.shalehah@dailyreportlka.app', 'ULIS PONSEL', 'MUARA TEWEH'),
  ('THALHAH', 'pc.thalhah@dailyreportlka.app', 'RIFA I PONSEL', 'MUARA TEWEH'),
  ('ULFAH', 'pc.ulfah@dailyreportlka.app', 'RANDE PONSEL', 'MUARA TEWEH'),
  ('M. ILHAM NASIR', 'pc.m.ilham.nasir@dailyreportlka.app', 'MITRA LL', 'MUARA TEWEH'),
  ('WAHYUDI AL AMIN', 'pc.wahyudi.al.amin@dailyreportlka.app', 'MITRA LL', 'MUARA TEWEH'),
  ('SATARIAN', 'pc.satarian@dailyreportlka.app', 'KARYA BARU', 'MUARA TEWEH'),
  ('NADYA PURNAMA SARI', 'pc.nadya.purnama.sari@dailyreportlka.app', 'IKA PONSEL', 'MUARA TEWEH'),
  ('ADELIA SEKAR PERMATA', 'pc.adelia.sekar.permata@dailyreportlka.app', 'HUMAIRA CELL', 'MUARA TEWEH'),
  ('AHMAD YANI AKBAR', 'pc.ahmad.yani.akbar@dailyreportlka.app', 'HAPIDZ PONSEL', 'MUARA TEWEH'),
  ('NURAHMAN', 'pc.nurahman@dailyreportlka.app', 'DHONAL PONSEL', 'MUARA TEWEH'),
  ('GITA', 'pc.gita@dailyreportlka.app', 'CV SURYA INDAH', 'MUARA TEWEH'),
  ('DARMAWAN', 'pc.darmawan@dailyreportlka.app', 'CERIA PONSEL TIMPAH', 'MUARA TEWEH'),
  ('LIE ERVENDI', 'pc.lie.ervendi@dailyreportlka.app', 'METRO PONSEL', 'PANGKALANBUN 1'),
  ('KHAIRULLAH AKHMAD', 'pc.khairullah.akhmad@dailyreportlka.app', 'ZONA CELL P.BUN', 'PANGKALANBUN 1'),
  ('UTIN SONIA FEBRIANTI', 'pc.utin.sonia.febrianti@dailyreportlka.app', 'SUKSES MAKMUR. CV', 'PANGKALANBUN 1'),
  ('DEWI NOR YULIANTI', 'pc.dewi.nor.yulianti@dailyreportlka.app', 'SUKSES MAKMUR. CV', 'PANGKALANBUN 1'),
  ('DEVI RUSMALA SARI', 'pc.devi.rusmala.sari@dailyreportlka.app', 'SUKSES MAKMUR. CV', 'PANGKALANBUN 1'),
  ('JULKIFLI', 'pc.julkifli@dailyreportlka.app', 'SUKSES MAKMUR. CV', 'PANGKALANBUN 1'),
  ('NINDI AYU ASTIRA', 'pc.nindi.ayu.astira@dailyreportlka.app', 'HERMAN CRISTIAN-EVENT', 'PANGKALANBUN 1'),
  ('SALWA SYAKILLA RAMADHANI', 'pc.salwa.syakilla.ramadhani@dailyreportlka.app', 'HERMAN CRISTIAN', 'PANGKALANBUN 1'),
  ('LUCI LAUZA SAHIRA', 'pc.luci.lauza.sahira@dailyreportlka.app', 'CHIPTA CELL', 'PANGKALANBUN 1'),
  ('FAIS CATHERINE', 'pc.fais.catherine@dailyreportlka.app', 'SUKSES MAKMUR. CV', 'PANGKALANBUN 1'),
  ('SUMARDI', 'pc.sumardi@dailyreportlka.app', 'YUNI PONSEL', 'LAMANDAU'),
  ('ELFIANI KHOLISNA SALSABILA', 'pc.elfiani.kholisna.salsabila@dailyreportlka.app', 'SUPER CELL_LAMANDAU', 'LAMANDAU'),
  ('DATIK PRIHATIN', 'pc.datik.prihatin@dailyreportlka.app', 'SUPER CELL_DESPOT', 'LAMANDAU'),
  ('A AN DAENI', 'pc.a.an.daeni@dailyreportlka.app', 'STAR SELINDO', 'LAMANDAU'),
  ('SELVINA RAHMADANI', 'pc.selvina.rahmadani@dailyreportlka.app', 'STAR PHONE 3', 'LAMANDAU'),
  ('LIYANTO', 'pc.liyanto@dailyreportlka.app', 'SMILE CELL', 'LAMANDAU'),
  ('MUHAMMAD MAHFUZH AMIN', 'pc.muhammad.mahfuzh.amin@dailyreportlka.app', 'SAUDI PONSEL', 'LAMANDAU'),
  ('EGY FARADILA', 'pc.egy.faradila@dailyreportlka.app', 'PELANGI PONSEL LAMANDAU', 'LAMANDAU'),
  ('SITI MUNASAROH', 'pc.siti.munasaroh@dailyreportlka.app', 'NAYA CELL LAMANDAU', 'LAMANDAU'),
  ('AINUN NISA', 'pc.ainun.nisa@dailyreportlka.app', 'JASA BERSAMA PONSEL DESPOT', 'LAMANDAU'),
  ('RIKA MARWATI', 'pc.rika.marwati@dailyreportlka.app', 'FLOREN CELL', 'LAMANDAU'),
  ('ZENNY YANI', 'pc.zenny.yani@dailyreportlka.app', 'FARSHAD CELL', 'LAMANDAU'),
  ('NUR RAHMANINGSIH', 'pc.nur.rahmaningsih@dailyreportlka.app', 'DONATUS', 'LAMANDAU'),
  ('AGUS SUSILO', 'pc.agus.susilo@dailyreportlka.app', 'BINTANG CELL', 'LAMANDAU'),
  ('BAYU SUSENO', 'pc.bayu.suseno@dailyreportlka.app', 'AVILLA PHONE', 'LAMANDAU'),
  ('AHMAD RIDHA', 'pc.ahmad.ridha@dailyreportlka.app', 'PG STORE', 'PURUK CAHU'),
  ('MELISA', 'pc.melisa@dailyreportlka.app', 'ILHAM CELL', 'PURUK CAHU'),
  ('MUHAMMAD ZAINI', 'pc.muhammad.zaini@dailyreportlka.app', 'ALEK CELL', 'PURUK CAHU'),
  ('MUHAMMAD YUDI', 'pc.muhammad.yudi@dailyreportlka.app', 'AFE CELLULAR', 'PURUK CAHU'),
  ('JULFIA AYU LESTARI', 'pc.julfia.ayu.lestari@dailyreportlka.app', 'RAMA PONSEL', 'PURUK CAHU'),
  ('NADILA', 'pc.nadila@dailyreportlka.app', 'RAMA PONSEL', 'PURUK CAHU'),
  ('NABILA AI''SA PUTRI', 'pc.nabila.ai.sa.putri@dailyreportlka.app', 'CV. BERKAT ANUGERAH SOLUSINDO', 'SAMPIT KOTA 2'),
  ('NURIYAH', 'pc.nuriyah@dailyreportlka.app', 'ERAFONE SPT 02', 'SAMPIT KOTA 2'),
  ('MOZA ANISA SAFITRI', 'pc.moza.anisa.safitri@dailyreportlka.app', 'TABRIIZ CELL', 'SAMPIT KOTA 2'),
  ('AHMAD DAVIN ALGIFARI', 'pc.ahmad.davin.algifari@dailyreportlka.app', 'BIMA PONSEL', 'SAMPIT KOTA 2'),
  ('HERLINA', 'pc.herlina@dailyreportlka.app', 'STAR PHONE', 'SAMPIT KOTA 2'),
  ('MUFARIKHAH ANGGRAENI', 'pc.mufarikhah.anggraeni@dailyreportlka.app', 'PELANGI SELULER CV', 'SAMPIT KOTA 2'),
  ('ERA NOVALLISTI', 'pc.era.novallisti@dailyreportlka.app', 'ERAFONE SPT', 'SAMPIT KOTA 2'),
  ('KLINDRI KLARANA', 'pc.klindri.klarana@dailyreportlka.app', 'DUNIA ELEKTRONIK', 'SAMPIT KOTA 2'),
  ('MULIANTHI', 'pc.mulianthi@dailyreportlka.app', '88 PONSEL', 'SAMPIT KOTA 2'),
  ('RABIATUL ADAWIYAH', 'pc.rabiatul.adawiyah@dailyreportlka.app', 'OPPO Store - Sampit', 'SAMPIT KOTA 2'),
  ('NELA WULANDARI', 'pc.nela.wulandari@dailyreportlka.app', 'BORNEO MULTI JAYA. CV', 'PANGKALANBUN 2'),
  ('FREDI LINTANG KUSUMO', 'pc.fredi.lintang.kusumo@dailyreportlka.app', 'PRIMA PONSEL', 'PANGKALANBUN 2'),
  ('TANZILLA NURDHIA ASRA', 'pc.tanzilla.nurdhia.asra@dailyreportlka.app', 'GLOBAL TOP RETALINDO. CV', 'PANGKALANBUN 2'),
  ('DESTI FITRIYANI', 'pc.desti.fitriyani@dailyreportlka.app', 'GLOBAL TOP RETALINDO. CV', 'PANGKALANBUN 2'),
  ('RIRIN ARUM KUSUMA', 'pc.ririn.arum.kusuma@dailyreportlka.app', 'GLOBAL TOP RETALINDO. CV', 'PANGKALANBUN 2'),
  ('RINA MARDIANA', 'pc.rina.mardiana@dailyreportlka.app', 'GLOBAL TOP RETALINDO. CV', 'PANGKALANBUN 2'),
  ('UTIN AMELIA PUTRI DEWI', 'pc.utin.amelia.putri.dewi@dailyreportlka.app', 'ERAFONE PANGKALANBUN 2', 'PANGKALANBUN 2'),
  ('NUR SYAHRUL RAHMADHANI', 'pc.nur.syahrul.rahmadhani@dailyreportlka.app', 'OPPO Store - Pangkalan Bun', 'PANGKALANBUN 2'),
  ('SILVI RESGITA PUTRI RISANTI', 'pc.silvi.resgita.putri.risanti@dailyreportlka.app', 'ROBY CELL', 'KASONGAN'),
  ('SINTA WULANDARI', 'pc.sinta.wulandari@dailyreportlka.app', 'JONI PONSEL 3', 'KASONGAN'),
  ('ISTIKAMAH', 'pc.istikamah@dailyreportlka.app', 'JONI PONSEL 2', 'KASONGAN'),
  ('NURMAULIDDAH', 'pc.nurmauliddah@dailyreportlka.app', 'JONI PONSEL', 'KASONGAN'),
  ('AHMAD AZMAN FIKRI', 'pc.ahmad.azman.fikri@dailyreportlka.app', 'GRAHA FITRAH CELL', 'KASONGAN'),
  ('SAPITRI', 'pc.sapitri@dailyreportlka.app', 'BERKAT USAHA', 'KASONGAN'),
  ('DZIKRUL HIDAYAH RAMADHANI', 'pc.dzikrul.hidayah.ramadhani@dailyreportlka.app', 'AL-WAFA CELLULAR', 'KASONGAN')
) v(nama, email, toko, area)
join public.areas a on a.nama = v.area
join public.stores s on s.nama = v.toko and s.area_id = a.id
on conflict (email) do update set nama = excluded.nama, store_id = excluded.store_id, aktif = true;

update public.profiles p set auth_uid = u.id
  from auth.users u
 where lower(u.email) = lower(p.email) and p.auth_uid is null;

select (select count(*) from public.profiles where role = 'trainer') as trainer,
       (select count(*) from public.profiles where role = 'sales') as sales,
       (select count(*) from public.areas) as area,
       (select count(*) from public.stores) as toko,
       (select count(*) from public.profiles where role = 'pc') as pc,
       (select count(*) from public.products) as produk_semua_area;
