# 18 — İlk Uğur adımı: gerçek danışan ölçümlerinin web görünümü

**Tarih:** 18.11.2026 · **İnceleme tabanı:** ortak `main`, `8f8a7a4`.
**Durum:** Ortak onaya sunulan öneri; uygulama veya kesinleşmiş API sözleşmesi değildir.

Kullanıcının son görev dağılımındaki ilk adım ele alınır: Mert kilo, bel,
kalça ve göğüs ölçümlerinin PostgreSQL/API ve Flutter kayıt akışını;
Uğur diyetisyen panelinde gerçek ölçümlerin okunmasını geliştirir.
Program karşılaştırması, yorumlar, görevler, su ve cihaz entegrasyonu sonraki
adımlardır. Bu belge bunların açık sözleşmelerini kapatmaz.

## Doğrulanan mevcut durum

| Kaynak | Bulgu | İlk adıma etkisi |
|---|---|---|
| `04/05/06` | `BodyMeasurement`, `measuredAt`, `weightKg`, `waistCm`, `bodyFatPercent`, `source` tanımlı | Mevcut adlar ve alanlar korunur |
| `05/06` | Kalça/göğüs ölçüm alanları henüz yok | Mobil, backend ve web için iki alanın ortak adı/tipi kesinleşmeli |
| `06` | `GET /api/v1/dietitian/clients/{clientId}/body-measurements` mevcut katalogda | Yeni rota veya alias gerekmez |
| `backend/src/SmartNutrition.Api` | Ölçüm entity/EF eşlemesi, migration, kendi kayıt ve diyetisyen okuma uygulaması yok | Gerçek web bağlantısı Mert'in saklama/API teslimine bağlı |
| `Features/Relationships` | Yalnız `nutrition_plans` ve `meal_logs` kategorileri uygulanmış | Bu izinler ölçüm erişimi için kullanılamaz |
| `apps/web/src/features/clients` | Ölçüm tipi/liste bileşeni yalnız sentetik önizlemede kullanılıyor | Mevcut sunum gerçek danışan detayında tekrar kullanılabilir |

## M1 — Ortak ölçüm alanları önerisi

`BodyMeasurement` korunur; ayrı kilo, kalça veya göğüs entity'si oluşturulmaz.
Mevcut alanlara yalnız aşağıdakiler eklenir:

| Ölçüm | Önerilen JSON / Dart / TypeScript adı | C# karşılığı | Tip / birim |
|---|---|---|---|
| Kalça çevresi | `hipCm` | `HipCm` | Nullable decimal / JSON number; cm |
| Göğüs çevresi | `chestCm` | `ChestCm` | Nullable decimal / JSON number; cm |

Yanıtın tüm alanları: `id`, `clientId`, `measuredAt`, `weightKg`, `waistCm`,
`hipCm`, `chestCm`, `bodyFatPercent`, `source`. Nullable anahtarlar yanıtta açık
null bulunur; bilinmeyen değer sıfır veya önceki ölçümle doldurulmaz.
`createdAt`, özet, hedef veya klinik yorum alanı bu yanıtın parçası yapılmaz.

Mevcut kurallar iki yeni çevre ölçümüne de uygulanır: bilinen kg/cm değerleri
sonlu ve pozitif, yağ oranı 0–100; son kayıtta beş ölçümden en az biri dolu
olur. Yeni zorunlu ölçüm veya klinik alt/üst sınır eklenmez. `RecordSource`
değerleri korunur; cihaz verisinin manuel yazmayla üretilmesi onaylanmaz.
Yazma DTO'su, EF/migration ve manuel kayıt uygulamasının lideri Mert'tir;
bu okuma önerisi saklama ölçeği/yuvarlama veya silme süresi seçmez.

## M2 — Bağımsız ölçüm paylaşımı önerisi

- Mevcut `DataSharingPermission` modeline ek kategori kodu `body_measurements`
  önerilir; yalnız bu kategorinin diyetisyen ölçüm okumasını açması kabul edilir.
  `nutrition_plans`, `meal_logs` ve diğer kategoriler bağımsız kalır.
- Mevcut izin yolları/JSON alanları kullanılır. `consentRecordId` bu dilimde
  null/atlanmış olur; tahlil açık onayı bundan türetilmez.
- Yalnız aktif ilişkinin danışanı kendi iznini açar/geri çeker. İlişki kabulü,
  yeni kategori veya migration otomatik izin/backfill oluşturmaz.
  Eksik/false izin kapalıdır; diyetisyen/Admin danışan adına izin veremez.
- İlişki/kategori unique kuralı korunur. Uğur'un izin migration'ı yalnız mevcut
  kategori check kısıtını genişletir; Mert'in ölçüm tablolarını oluşturmaz.
  Geri alma `body_measurements` izin satırlarını silerek zorlanmaz.
- Mobil ayrıştırıcı yeni kategoriye uyarlanmadan yeni izin satırı açılmaz.
  Önerilen dahili `Relationships:Sharing:BodyMeasurementsEnabled` ayarı
  varsayılan false olur. Kapalıyken yeni ölçüm izni POST'u ve PATCH true 422;
  mevcut izni geri çeken PATCH false izinlidir. Ayar mevcut izinleri gizlemez,
  silmez ve okuma yetkisinin yerine geçmez. Ortak ortamda açılmadan önce Mert'in
  mobil kategori/sayfalama uyarlaması aynı `main` sürümüyle doğrulanır.

## M3 — Mevcut diyetisyen okuma yolunun önerilen ayrıntıları

`GET /api/v1/dietitian/clients/{clientId}/body-measurements` korunur.

| Parça | Öneri |
|---|---|
| İstek | Gövdesiz; zorunlu `page`, `pageSize`; isteğe bağlı `from`, `to`; başka query yok |
| Sayfalama | `page >= 1`, `pageSize` 1–100; varsayılan yok; web açıkça 10 gönderir. Int32 offset taşması ve tekrarlı/bozuk query 400 |
| Zaman | `measuredAt` için from dahil, to hariç; açık UTC/ofsetli instant; iki sınır varsa from < to. Ofsetsiz/boş/geçersiz sınır 400 |
| Sıra | measuredAt azalan, eşitlikte id artan; filtre/sıra sayfalama öncesinde |
| Başarı | `200 { items, totalCount }`; satırlar M1'deki alanları taşır. Sayı yalnız izinli/filtrelenmiş kayıtlardır; yetkili boş küme gerçekten boş döner |
| Kimlik | Mevcut W2 HTTPS cookie veya JWT; güncel doğrulanmış hesap, onaylı DietitianProfile, aktif ilişki ve M2 izni her okumada sunucuda kontrol edilir |
| Profil | `X-Profile-Context: dietitian`; temel rolü client olan onaylı çift profil kabul edilir. Başlık tek başına yetki vermez |
| Hata | Oturumsuz 401; uygun olmayan/onaysız uzman veya Admin 403; yabancı/olmayan danışan ya da aktif olmayan ilişki 404; kendi aktif ilişkisinde eksik/false ölçüm izni 403 |
| Tutarlılık | Kimlik, ilişki, izin, sayı ve satırlar aynı DB snapshot'ında; commit edilmiş iptal/sonlandırmadan sonra başlayan okuma kapalıdır |
| Gizlilik | Tüm yanıtlar no-store, hatalar mevcut ortak zarf; sağlık değerleri loglanmaz. Ağ/DB hatası boş listeye çevrilmez |

Diyetisyen tüketim/ölçüm kayıtlarını değiştiremez. Danışanın kendi ölçüm
erişimi ilişki veya paylaşım iznine bağlanmaz. Bu adım diyetisyen için yeni
detay/yazma yolu veya Dashboard sağlık alanı eklemez.

## M4 — İlk gerçek web ekranı ve kabul kontrolleri

Uğur mevcut gerçek danışan detayına salt okunur ölçüm bölümünü ekler;
mevcut `BodyMeasurementList` sunumunu M1'e göre uyarlar. Kaynak, zaman,
kg/cm/yüzde ve bilinmeyen değerler açık gösterilir. Sunucudan sayfalama,
UTC olduğu belirtilen tarih-saat filtresi ve elle yenileme bulunur.
İzin kapalı, bağlantı bitmiş, yükleniyor, yetkili boş sonuç ve hata ayrıdır.
Danışan/oturum/filtre/sayfa değişince önceki veri ve sayılar kaldırılır;
iptal edilmiş isteklerin geç yanıtları gösterilmez. Sentetik veriye dönüş yoktur.

Uğur'un bu ilk adımı grafik, BMI, başarı puanı veya hedef yorumu üretmez.
Listedeki ikinci ve sonraki işlere ayrıca geçilir.

Uygulama sonrasında doğrulanacaklar (henüz çalıştırılmış test değildir):

1. Program/öğün izni ölçüm açmaz; ölçüm izni diğer verileri açmaz. Admin,
   onaysız/yabancı uzman, aktif olmayan ilişki, eksik/geri çekilmiş izin reddedilir.
2. Kendi ölçümüne erişen danışan ilişki olmasa da kaydını okuyabilir.
3. Kalça/göğüs/bel/kilo/yağ nullable değerleri ve ondalık sayılar web/mobilde aynı
   anahtarlarla ayrıştırılır; başka danışanın kaydı ve yanlış yanıt tipi gösterilmez.
4. Sayfalama, UTC/ofset sınırları, eşit zamanların kararlı sırası, iptal ve geç
   yanıtlar; mobil izin kategorisi/sayfalama regresyonu doğrulanır.
5. Uğur'un ilgili backend testleri sentetik geçici PostgreSQL'de; web testleri,
   typecheck/lint/build ve iki temada duyarlı düzen kontrolü çalıştırılır.
6. Mert'in manuel kayıt API'siyle oluşturulan sentetik ölçüm gerçek web panelinde
   okunur; paylaşım geri çekildikten sonraki okumada kayıt/sayı gösterilmez.

## Onay ve uygulama sırası

M1–M4 iki geliştiricinin ortak onayından sonra `04/05/06`ya geçirilir;
uygulama/güvenlik/istemci etkileri `08/11/12` ile eşgüdümlü ele alınır.
Bu belge tek başına mevcut kanonik sözleşmeleri değiştirmez.

1. Mert M1'e uygun ölçüm saklama/API ve Flutter kayıt/paylaşım uyarlamasını
   üstlenir; Uğur aynı C# entity/migration dosyalarına paralel yazmaz.
2. Uğur M2 izin altyapısını, Mert'in gerçek ölçüm kaynağı hazır olduğunda M3
   diyetisyen okumasını ve M4 React ekranını geliştirir.
3. Ortak onaylı sözleşme ve gerekli uygulamalar `main` üzerinden eşitlenir;
   mobil uyumluluk doğrulanmadan yeni kategori ortak ortamda açılmaz.
4. İlk adım gerçek sentetik kayıtla uçtan uca doğrulandıktan sonra listedeki
   program–gerçekleşen karşılaştırmasına geçilir.

Commit/push/PR bu belgeyle yetkilendirilmez. Bu görevde `04/05/06`, backend,
Flutter ve React uygulaması değiştirilmemiştir.
