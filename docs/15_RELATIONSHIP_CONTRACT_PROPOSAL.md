# 15 — 29 Ekim ilişki, davet ve paylaşım dilimi

**Tarih:** 29.10.2026 · **Durum: R1–R3 ORTAK ONAYLI.** Kullanıcı
“R1–R3 için ortak onay var; uygula.” yanıtıyla iki tarafın onayını teyit etti.
Güncel normatif kaynak `04/05/06`dır. Lider Uğur; web ve ilgili backend,
Flutter kaynaklarına yazılmaz. Program paketinin ayrıntıları açık kalır.

## R1 — davet ve karşılıklı onay

- Kanonik `DietitianClientRelationship`, mevcut alan/enum/yollarıyla kullanılır.
  Danışan talebi başlatır, hedef doğrulanmış diyetisyen kabul/red verir.
  Admin veya başka hesap bu işlemleri taraf adına yapamaz.
- Mevcut `POST /dietitian-relationships` için `dietitianId` veya yeni
  `invitationCode` alanından **tam biri** gönderilir; clientId auth User →
  ClientProfile üzerinden bulunur. Başarı `201` mevcut pending ilişki DTO'su.
  Arama ve kod aynı karşılıklı onay sürecini başlatır; kod aktif ilişki yaratmaz.
- Diyetisyen için yeni `POST /dietitians/me/invitation-code`, gövdesiz,
  yalnız e-postası ve uzmanlığı doğrulanmış hesap. `200 InvitationCodeResponse`
  `{ invitationCode, expiresAt }`. Kod kriptografik rastgele 80 bit,
  16 büyük Base32 karakter; 24 saat, tek kullanımlık. Yeni kod eskisini iptal
  eder; mevcut ilişkileri değiştirmez. Kod yalnız bu yanıtta görünür.
- DietitianProfile'a yalnız sunucu `invitationCodeHash: string?` (SHA-256,
  64 hex) ve `invitationCodeExpiresAt: instant?` eklenir. Ham kod saklanmaz,
  loglanmaz veya public uzman/başvuru durum yanıtına eklenmez. Kodun tüketimi
  pending ilişki eklemeyle aynı transaction'dadır; başarısız ekleme kodu tüketmez.
- Kendi aktif ilişkisinin bulunması yeni talebe `409`; aynı çifte ikinci
  pending talep `409`. Farklı uzmanlara pending talepler bulunabilir.
  Kabulde başka aktif ilişki varsa `409`; diğer pending kayıtlar sessizce
  kabul/red durumuna geçirilmez. ClientProfile satır kilidi ve PostgreSQL
  kısmi unique indeks aktif ilişki yarışını engeller. Aynı çiftin pending
  kaydı için de kısmi unique indeks olur; geçmiş silinmez.
- Mevcut accept/reject yolları yalnız hedef diyetisyene aittir. Kabulde
  status=active, respondedAt=now; redde status=rejected, respondedAt=now.
  Aynı sonuca tekrar istek `200` ve değişmeyen zaman; diğer geçersiz geçiş `409`.
- Mevcut end yolu iki tarafın kendi pending veya active ilişkisini bitirir:
  status=ended, endedAt=now; pending'de respondedAt null kalır. Aynı ended
  kaydı tekrar `200`; rejected kayıtta end `409`. Aktif ilişkinin bitişi
  diyetisyenin yeni erişimini keser; eski programın sahipliği değiştirilmez.
- GET ilişkiler yalnız oturum sahibinin tarafı olduğu mevcut alanları ortak
  liste zarfıyla döndürür. page/pageSize zorunlu; istenirse mevcut status
  değerlerinden filtre; sıra requestedAt azalan, ardından id.
- Talep/kod üretiminde ayrı yapılandırılabilir hesap+IP başına 5/dakika
  limit; hatalı/bilinmeyen/süresi dolmuş/tüketilmiş kod tek genel `422`.
  Başka tarafın ilişki kimliği `404`; geçerli kimlikle yanlış işlem rolü `403`.
  Yazmalar bearer veya W2 cookie kullanır; cookie yazmasında W2 CSRF/Origin
  zorunludur. İki kimlik birlikte gönderilmez; istemci userId göndermez.

## R2 — ilk kategori ve varsayılan kapalı paylaşım

- `DataSharingPermission` mevcut alanları/yollarıyla uygulanır. Bu ilk
  dilimde tek onaylı kategori kodu **`nutrition_plans`**; ürün etiketi
  “Beslenme programları”. İlişkinin kabulü otomatik izin oluşturmaz.
  İzin kaydı yok veya isGranted=false ise diyetisyene program erişimi yoktur.
- İzin yalnız ilişkinin danışanı tarafından aktif ilişkide oluşturulur veya
  güncellenir. POST aynı ilişki/kategoride ikinci kayda `409`; PATCH yalnız
  isGranted değiştirir. relationshipId/category/sahiplik değiştirilemez.
  İlişki aktif değilse yazma `409`; başka tarafın kaydı `404`.
- GET izinler, zorunlu relationshipId/page/pageSize ile yalnız kendi
  ilişkisinin kayıtlarını ortak liste zarfıyla okur; diyetisyen kendi
  ilişkisinin izin durumunu okuyabilir, değiştiremez.
- Bu kategoride consentRecordId daima null'dır; dolu değer veya başka
  kategori `422`. Bu dilim tahlil açık onayı veya hukuki metin tasarımı
  değildir. Diğer sağlık kategorileri/ConsentRecord tür-politika kanıtı
  karara bağlanana kadar kapalıdır; tahlil/öğün/su/ölçüm/aktivite erişimi açılmaz.
- İzin ve ilişkinin güncel durumu her kaynak işleminde DB'den denetlenir;
  geri çekme/sonlandırma yeni erişimi keser. Danışanın kendi program erişimi
  diyetisyen ilişkisinden bağımsız kalır. Verinin geçmişi silinmez; saklama
  ve silme politikası için `11` yayın kapısı korunur.

## R3 — gerçek web bağlantı istekleri ve danışan listesi

- `GET /dietitian/clients`: doğrulanmış diyetisyenin aktif ilişkili
  danışanları; `{ items: [{ id, displayName }], totalCount }` mevcut temel
  sözleşmesi korunur. Sağlık değeri, doğum tarihi/boy veya hedef eklenmez.
- page/pageSize zorunlu; opsiyonel query görünen ad üzerinde harf duyarsız
  literal arama; opsiyonel sortOrder yalnız asc/desc (gönderilmezse asc).
  Eşit adlarda id sırası kararlıdır. Bu modül sunucu liste üst limiti seçmez;
  mevcut pozitiflik/int32 offset taşması kuralları uygulanır. Web 10 gönderir.
- `GET /dietitian/clients/{clientId}/dashboard` için açık tam sağlık özeti
  yerine bu dilimde onaya sunulan minimal `ClientDashboardResponse` yalnız
  `{ clientId, displayName }` içerir. Aktif ilişkili olmayan kaynak `404`;
  daha sonraki sağlık bileşenleri kendi kategori/DTO onaylarıyla eklenir.
- Bu iki yanıt yalnız ilişki kapsamındaki temel kimlik/görünen addır;
  sağlık kategori izni varmış gibi değer/toplam/trend sunulmaz. Gelecek
  program işlemleri ayrıca R2 iznini ister; Admin bu endpointleri kullanamaz.
- Webde gerçek diyetisyen alanı sunucudan auth/me + dietitians/me ile
  doğrulanır. Doğrulanmamış uzman başvuru durumunu görür. Bağlantı istekleri
  kabul/red/sonlandırma ve davet kodu üretimi API'ye bağlanır; danışan
  listesi/detayı gerçek sınırlı veriyi gösterir. Önizleme ayrı kalır.
- Yüklenme/boş/hata durumları gerçek istek sonucudur. 401/403 ve bağlam
  değişiminde özel görünüm temizlenir; CSRF değişiminde yazma otomatik
  tekrarlanmaz. Sahte danışan/öğün/program başarı mesajı üretilmez.

## Etki, kabul ve açık sınırlar

**Doğrulama:** Gerçek PostgreSQL/Mailpit ile 240 backend testi geçti, 0
atlandı. Kabul yarışı, tek active DB indeksi, kod rotasyonu/tüketim/expiry ve
rollback, izin geri çekme/ilişki sonu, sahiplik ve CSRF test edildi. Webde
115 test, typecheck/lint başarılı. Flutter kaynaklarında fark yoktur.

- Ortak onaydan sonra `04/05/06/11/12` + backend migration/servis/HTTP/yetki
  testleri ve web birlikte güncellenir. Mobil DTO etkisi belgelenir; Mert
  ortak main'i çektikten sonra kendi istemci entegrasyonunu yapar.
- Test: kod rotasyonu/tüketimi/expiry ve rollback; aynı anda kabulde tek
  aktif ilişki; başka kullanıcı kimliği/sahipliği; pending/ended erişim
  reddi; izin geri çekme, kendine erişimin korunması; CSRF/Origin; gerçek
  liste filtresi/pagination ve web geç yanıt/çift gönderim/boş durumları.
- Bu paket NutritionPlan items/sürüm/alternatif/geçiş yapısını kapatmaz.
  Program oluşturma/atama sonraki somut pakettir. İlişki bitince programın
  aktif/arşiv davranışı o pakette kararlaştırılır; owner değiştirilmez.
- **Ortak onay kaydı:** Kullanıcının açık teyidi: “R1–R3 için ortak onay var; uygula.”
