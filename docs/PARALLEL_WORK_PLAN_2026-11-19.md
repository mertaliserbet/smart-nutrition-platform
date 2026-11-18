# Smart Nutrition Platform — Mert & Uğur Paralel Geliştirme Koordinasyonu

> **Dosyanın repo içindeki konumu:** `docs/PARALLEL_WORK_PLAN_2026-11-19.md`  
> **Sürüm:** 1.4 · **Hazırlanma:** 18.11.2026 · **U4 güncelleme:** 19.11.2026 · **Bitirme toplantısı:** 19.11.2026
> **Kapsam:** Mevcut Smart Nutrition Platform. İptal edilmiş fitness/Trainer/openGym projesi bu planın parçası değildir.

## 1. Bu dokümanın amacı ve geçerliliği

### 19.11.2026 — U4 uygulama ve doğrulama kaydı

- U3 birleştirilmiş `99611a4` main'de başladı; çalışma ağacı temiz, migration
  sırası/snapshot tutarlıydı. Yeni migration `20261118230136_AddWaterLogSharingCategory`
  yalnız kategori check'ini genişletir; tablo/index/backfill/otomatik izin eklemez.
  Su kayıtları ve diğer izinler korunur, false dahil su izin satırında Down reddedilir.
- Bağımsız water_logs, varsayılan false WaterLogsEnabled açılımı, uzman liste/
  günlük toplam/31 günlük IANA geçmişi ve gerçek React WaterLogPanel hazırdır.
  Güncel doğrulanmış uzman + kendi active ilişkisi + açık su izni; veri ve yetki
  aynı snapshot. Kendi su CRUD/kişisel hedef davranışı korunur, hedef paylaşılmaz.
  Kaynak/tarih/saat/mL, 10'lu liste, SVG grafik/tablo, izin/hata/boş ayrımı,
  AbortController ve görünür sekme yenilemesi uygulanır; paket eklenmedi.
- `dotnet build SmartNutrition.Backend.slnx --no-restore`: **0 hata/0 uyarı**.
  Geçici PostgreSQL 17 `127.0.0.1:55584/nutrition_u4_test`; yalnız sentetik veri,
  ayrı test DB/schemaları, eski Auth testleri için yalnız test DB temel şeması.
  Uygulama DB'sine migration uygulanmadı.
- İlgili API/izin/su/altyapı filtresi: **61/61**. Tam
  `dotnet test SmartNutrition.Backend.slnx --no-build --no-restore`: **479 başarılı,
  0 başarısız, 2 Mailpit testi atlandı, toplam 481**; yeni U4 PostgreSQL API
  testleri **11/11**. Danışan su oluştur→izin ver→uzman cookie oku→geri al→403,
  izin bağımsızlığı/default kapalı, ilişki/uzman/rol/sahiplik, salt okunurluk,
  mL/silme/sayfa/boş gün/DST, snapshot iptal yarışı, 500≠0 ve migration veri
  koruma/Down reddi gerçek PostgreSQL üzerinde geçti.
- Son `node node_modules/vitest/vitest.mjs run --maxWorkers=2`: **319 başarılı,
  0 başarısız, 3 opt-in canlı test atlandı; 22 dosya**. U4 su testleri **37/37**;
  gerçek DTO biçimi, liste/toplam/geçmiş, sınır/hata, izin iptali, geç tarih/
  danışan yanıtı, oturum değişimi, görünürlük/poll ve mikro-saniye/offset sırası.
  İlk tam web turu 317 başarılıydı; ek iki regresyon sonrası tekrar geçti.
  `npm run build` ve `npm run lint` başarılı. Yeni testteki string source tipi
  derleme bulgusu yalnız test tipi daraltılarak düzeltildi; test/build tekrar geçti.
- `dotnet ef migrations has-pending-model-changes --project src/SmartNutrition.Api --no-build`:
  değişiklik yok; `git diff --check` temiz. Geçici test PostgreSQL'i kapatıldı;
  TRX sonuçları yerel artifacts'ta tutulur. Başlangıçta olmayan EF history tablosu
  test DB kurulumu sırasında oluşturuldu; uygulama DB'si kullanılmadı.
- Dosyalar: backend WaterLogService, yeni DietitianWaterLogsController/WaterLogCalendar;
  RelationshipModels/DataSharingPermissionsController/appsettings; kategori migration,
  Designer/snapshot; yeni DietitianWaterLogApiTests, RegistrationApiFactory ve
  InfrastructureTests. Web yeni WaterLogPanel/WaterLogPanel.test/waterLogApi,
  LiveClientsPage, ClientRecordViews ve clientTracking.css. Backend/web README,
  docs 04/05/06/08/11/12/21 ve bu koordinasyon belgesi eşitlendi.
- M4 bağımlılığı: mevcut mobil kategori listesi/katı ayrıştırıcı ve en çok dört
  satır sınırı beş kategoriye uyarlanmalı; su kontrolü ve bağımsız POST/PATCH
  doğrulanmadan WaterLogsEnabled ortamda açılmaz. Tam örnekler
  [21_WATER_LOG_SHARING_CONTRACT.md](21_WATER_LOG_SHARING_CONTRACT.md).
  Flutter ve fiziksel tarayıcı/cihaz doğrulaması yapılmadı; React DOM/API testi
  bunların yerine bildirilmez. mobile/AGENTS/kök yapılandırmaları değişmedi.
  Git fetch/pull/dal/geçmiş/commit/push yapılmadı, U5 başlatılmadı.

### 19.11.2026 — U3 uygulama ve doğrulama kaydı

- U1 `20261118204842_AddClientTasks` mevcut, başlangıç model/snapshot kontrolü temizdi.
  Yeni migration `20261118222117_AddHealthDataSync`; sıra korunur, eski migration
  silinmedi/yeniden adlandırılmadı. Beş yeni tablo ve sahiplik/unique/check kısıtları;
  eski tabloların içerik fingerprint'i korundu, veri varken Down reddedilir.
- ActivityLog/WearableConnection kanonik kaldı; HealthData feature kaynak başlığı,
  skaler/nabız örnekleri, atomik batch receipt ve conservative_overlap_v1 gerçek
  günlük özetini uygular. Yalnız kendi client JWT'si; kategori/diyetisyen/Admin
  erişimi açılmaz. M1 kodu okundu, değiştirilmedi. Somut M3 DTO ve örnekler:
  [20_HEALTH_DATA_SYNC_CONTRACT.md](20_HEALTH_DATA_SYNC_CONTRACT.md).
- `dotnet build SmartNutrition.Backend.slnx --no-restore`: **0 hata, 0 uyarı**.
  Ayrı geçici PostgreSQL 17 / `127.0.0.1:55583/nutrition_u3_test` kullanıldı;
  testler sentetik ve disposable schema'larda, eski Auth testleri için test DB
  temel şeması ayrıca hazırlandı. Uygulama DB'sine migration uygulanmadı.
- `dotnet test SmartNutrition.Backend.slnx --no-build --no-restore`: **468 geçti,
  0 başarısız, 2 atlandı, toplam 470**. U3'e ait **20 PostgreSQL/API testi** geçti:
  sahiplik/rol/profil, kaynak/birim/zaman, DST/gün sınırı, import→retry→update→read,
  HR kısmi pencere/nokta silme, grup silme, idempotency/sürüm yarışı, iptal yarışı,
  transaction rollback, HTTP 512 KiB/batch sınırı, örtüşme ve gerçek şema adları.
  Atlanan iki SMTP testi Mailpit ister; sağlık testi atlanmadı.
- `dotnet ef migrations has-pending-model-changes --project src/SmartNutrition.Api --no-build`:
  değişiklik yok. `git diff --check`: temiz. İlk tam turdaki boş test DB hatası
  test şeması hazırlanarak giderildi; U1 migration testi kendi migration hedefiyle
  sınırlandı. Yeni uzun indeks adı gerçek şemayla karşılaştırılarak düzeltildi.
- Değişen alanlar: backend HealthData (model, DTO, doğrulama, controller, sync,
  ActivityLog ve özet servisleri); AppDbContext/Program/ApiErrors; yeni migration,
  Designer ve snapshot; iki U3 test dosyası ve InfrastructureTests/ClientTaskApiTests;
  backend README ile docs 01/03/04/05/06/11/12/20 ve bu koordinasyon belgesi.
  mobile/apps/web/AGENTS/kök yapılandırması değişmedi; Git dalı/geçmişi değiştirilmedi,
  commit/push yapılmadı. Test PostgreSQL'i kapatılır, TRX sonuçları yerel test artifacts'ta tutulur.
- Fiziksel Android/iOS Health Connect/HealthKit doğrulaması ve M3 mobil HTTP
  entegrasyonu yapılmadı; bu backend testlerinden cihaz sonucu çıkarılmaz.
  Sıradaki bağımlılık: U3 ortak main'e alındıktan sonra Mert'in ayrı M3 entegrasyonu.

Bu belge **iki ayrı Codex oturumunun aynı özellikleri yeniden geliştirmesini, birbirinin değişikliklerini ezmesini ve EF Core migration çakışmalarını önlemek** amacıyla oluşturulmuştur. Her iki Codex, **her göreve başlamadan önce** bu belgeyi, `AGENTS.md` dosyasını, ilgili güncel sözleşmeleri ve kendi dalındaki kaynak kodu okumalıdır.

- Bu belge **görev sahipliği ve uygulama sırası** için ortak referanstır; API davranışının kaynağı güncel ve onaylı `docs/` sözleşmeleri ile çalışan koddur.
- **Uğur** bu aşamada paylaşılan backend, EF migration, ortak `docs/` sözleşmeleri ve React'in **tek yazma sorumlusudur**. **Mert** Flutter'ın tek yazma sorumlusudur.
- Her iki taraf daha önce geliştirilmiş kodu önce denetler. **Mevcut bir özelliği ikinci kez yazmak yasaktır.** Çakışmada yazmayı durdurup farkları raporlar.
- Bütün görevler küçük parçalara ayrılır. **Codex git pull, commit, push, merge, rebase veya dal değişikliği yapmaz**; bunları geliştiriciler kontrol eder. Her teslimin sonunda **kısa Türkçe durum raporu ve Türkçe commit mesajı önerisi** verilir.
- Buradaki durumlar önceki Codex raporlarına dayanır. **Git'te birleşmiş/ilgili dalda mevcut olup olmadığı ayrıca kontrol edilmeden “hazır” kabul edilmez.**

## 2. Şu ana kadar tamamlandığı raporlanan özellikler

| Özellik | Son raporlanan durum | Yeniden geliştirme kararı |
|---|---|---|
| Kayıt, e-posta doğrulama, oturum/JWT/refresh, Admin MFA | Temel akışlar mevcut | Gereksiz değişiklik yok |
| Diyetisyen başvuru/onay, eşleşme ve karşılıklı izinler | Backend + web + mobil temel akış mevcut | Gereksiz değişiklik yok |
| Atanmış beslenme programı / sürümler | Web atama, mobil görüntüleme mevcut | Korunacak |
| Öğün CRUD ve su CRUD | PostgreSQL + API + Flutter mevcut | Korunacak |
| Kişisel kalori/makro/su hedefleri | API + Flutter Dashboard mevcut | Korunacak |
| Vücut ölçümleri, mobil/web grafikler | API + Flutter + React mevcut | Korunacak |
| Program–gerçekleşen öğün karşılaştırması | API + React + Flutter mevcut | Korunacak |
| Diyetisyen öğün okuma ve bağımsız `meal_logs` izni | API + React + mobil izin yönetimi mevcut | Korunacak |
| Diyetisyen öğün yorumu ve danışan yanıtı | API + React + Flutter mevcut | Korunacak |
| `body_measurements` paylaşımı | Backend + mobil izin + web okuma mevcut | Korunacak |

**19 Kasım toplantısının doğrudan kalan iki ana başlığı:** (1) görev atama ve takip, (2) Health Connect/HealthKit ile izinli aktivite senkronizasyonu. Bunların dışındaki takip eksikleri de §5'te kayıtlıdır.

## 3. Dosya sahipliği — çakışma önleme kuralı

| Alan / yollar | Yazma sorumlusu | Diğer kişinin sınırı |
|---|---|---|
| `mobile/**` (Flutter, Android/iOS mobil yapılandırması, mobil testleri) | **Mert** | Uğur yalnızca okuyabilir |
| `apps/web/**` (React, web testleri) | **Uğur** | Mert yalnızca okuyabilir |
| `backend/**` (ASP.NET Core, testler, `AppDbContext`, `Program.cs`, migration/snapshot) | **Uğur** | Mert yalnızca okuyabilir; açık devir olmadan değiştirmez |
| `docs/**` ortak API, veri sözlüğü, güvenlik/sözleşme ve **bu koordinasyon belgesi** | **Uğur** (tek yazıcı) | Mert öneri verir; paralel düzenlemez |
| `start.ps1`, kök yapılandırmalar, CI/deploy, `AGENTS.md` | **Ortak değişiklik gerektirir** | Önceden onay almadan iki taraftan biri değiştirmez |
| Yerel PostgreSQL şeması / migration uygulama | **Uğur, koordineli** | Mert migration üretmez/uygulamaz; güncel şemayı doğrular |

**İstisna:** Acil bugfix için sahiplik devri gerekiyorsa önce **dosya listesi, neden ve değişikliği kimin yapacağı** yazılı olarak mutabık kalınır. Bu devir tamamlanana kadar diğer Codex ilgili dosyalara dokunmaz.

## 4. Kalan ana görevler — tekil kimlikler ve bağımlılıklar

### 4.1 Mert — Flutter ve mobil veri kaynağı

| ID | Görev | Başlama koşulu / teslim ölçütü | İzinli kod alanı |
|---|---|---|---|
| **M1** | Health Connect / HealthKit izin ve okuma altyapısı | **Hemen başlanabilir.** Desteklenen cihaz/veri türlerini incele, izin akışını kur; adım, mesafe, egzersiz, aktif kalori ve desteklenen nabız okumayı ele al. İzin reddi/veri yok/uyumsuz platform doğru gösterilsin. **Backend'e henüz dokunma.** | `mobile/**` |
| **M2** | Flutter görev yönetimi | **Ortak main'e d14576f ile alındı.** Atanan görev listesi/detay, durum geçişleri, son tarih/tamamlama/geçmiş ve client_tasks izin desteği mevcut. Uğur'un U2 oturumunda Flutter canlı doğrulaması yapılmadı; ortak web–Flutter provası ayrıca tamamlanır. | `mobile/**` |
| **M3** | Sağlık verisi API senkronizasyonu + aktivite ekranı | **U3 sağlık veri API'si birleştirilmiş olmalı.** İzinli kayıtları güvenle senkronize et; çoğaltma yapma; gerçek günlük özet, son senkronizasyon ve hata/boş durumları göster. | `mobile/**` |
| **M4** | Bağımsız `water_logs` paylaşım izni | **U4 izin kategorisi/API hazır ve birleştirilmiş olmalı.** İzin ver/geri al; `nutrition_plans`, `meal_logs`, `body_measurements` izinlerini değiştirme. | `mobile/**` |
| **M5** | Mobil şifre sıfırlama entegrasyonu | Mevcut reset backend sözleşmesini doğrula; gerçek API'yle parola sıfırlama ekranını tamamla; eski oturumların sonlanmasını test et. | `mobile/**` |
| **M6** | Mobil regresyon ve gerçek ekran kontrolü | Android emülatöründe Auth, öğün, su, hedef, ölçüm, karşılaştırma, yorum, görev ve izin akışları; demo verisi/sızıntı kontrolü. | Mobil test / rapor |

**M1 kuralı:** Sağlık verilerini Flutter tarafında okumak, U3 tamamlanmadan backend'e kaydedildiği anlamına gelmez. iOS/HealthKit fiziksel doğrulaması mümkün değilse açıkça “doğrulanmadı” yaz.

### 4.2 Uğur — Paylaşılan backend, sözleşmeler ve React

| ID | Görev | Başlama koşulu / teslim ölçütü | İzinli kod alanı |
|---|---|---|---|
| **U1** | Görev sistemi API + PostgreSQL | **PR #14 ile ortak main'e alındı (4a1cab4).** ClientTask API, bağımsız izin, durum/geçmiş/eşzamanlılık, veri koruyan migration ve testler hazır; kesin sözleşme `04/05/06`. Uygulama DB'sine migration ayrıca koordineli uygulanır. | `backend/**`, ilgili `docs/**` |
| **U2** | React görev atama ve takip | **Uygulandı/doğrulandı; ortak main entegrasyonu bekler.** Gerçek danışan çalışma alanında atama, liste/detay, düzenleme/iptal, geçmiş, 409 ve izin/ilişki kaybı. Mevcut API korunur; test sonuçları aşağıda. PR tabanı mobil M2'yi içeren d14576f'tir; Flutter canlı provası ayrıca yapılır. | `apps/web/**`, ilgili backend testleri ve docs |
| **U3** | Sağlık verisi API + PostgreSQL | **19.11 kullanıcı uygulama onayıyla kodlandı.** U1 dalda/snapshot tutarlı. Birim/tarih/kaynak/tekrar/izin sözleşmesi 04/05/06/20'de; yalnız danışanın kendi JWT'si, atomik sync, gerçek özet. Test sonuçları aşağıdaki U3 kaydındadır. | `backend/**`, ilgili `docs/**` |
| **U4** | Diyetisyen su görüntüleme | **19.11 kullanıcı onayıyla uygulandı.** Bağımsız water_logs, salt okunur liste/toplam/31 günlük IANA geçmişi ve gerçek React bölümü. Migration U3 sonrasındadır; varsayılan kapalı açılım, M4 teslim notu 21. Doğrulama kaydı aşağıdadır. | `backend/**`, `apps/web/**`, `docs/**` |
| **U5** | React şifre sıfırlama entegrasyonu | Var olan reset backend'ini koruyarak web formlarını gerçek API'ye bağla, Mailpit ile doğrula; Admin MFA'yı koru. | `apps/web/**` |
| **U6** | Web/backend regresyon testi | Diyetisyen panelinde program, gerçek öğün, yorumlar, karşılaştırma, ölçüm grafikleri, görevler ve su görüntüleme; gerçek oturum/izin iptali/CSRF/rol testi. | Backend/web test ve rapor |

**U1/U3 kuralı:** Kullanıcının ilgili uygulama talimatları ortak kararları onayladı; U1 ve U3 uygulanan sözleşmeleri esas alınır. U3 yalnız kendi sağlık verisidir, diyetisyen paylaşımı açmaz. Sonraki kapsam değişiklikleri ayrıca yetkilendirilir.

**U1 uygulama kaydı — 18–19.11.2026:** Kullanıcı U1 için gerekli ürün/teknik
kararları onaylı kabul ederek kalan ayrıntılarda mevcut mimariye göre ilerlemeyi
açıkça yetkilendirdi; bu görevde yeniden onay beklenmez. Yeni
`20261118204842_AddClientTasks` migration'ı uygulama DB'sine uygulanmadı.
client_tasks izni varsayılan kapalı; M2 kategori/sayfalama uyumu ve ortak main
entegrasyonu doğrulanmadan ClientTasksEnabled açılmaz. Görev liste/detay/atama/
PATCH ve `/client-tasks/{clientTaskId}/versions` sözleşmesi `06`dadır. Danışan
durum/hatırlatma tercihini, atayan uzman açıklama/son tarih/iptali yönetir;
ilişki sonu açık görevleri geçmişiyle atomik iptal eder. Bildirim teslimi yoktur.
U2/U3 başlatılmadı; Git işlemleri ve Flutter/React değişiklikleri yapılmadı.

**U1 doğrulama:** Ayrı geçici PostgreSQL 17.11'de son tam backend koşusu
447 başarılı / 2 opt-in Mailpit atlandı / 0 başarısız; 19 görev testi dahil.
Build 0 uyarı/hata; EF model–snapshot farkı yok; git diff --check temiz.
Uygulama DB migration'ı ve mobil/web uçtan uca prova yapılmadı. Sonraki tek
adım geliştiricilerin U1'i ortak main'e entegre edip M2 için bu sözleşmeyi paylaşmasıdır.

## 5. Toplantı dışından kalan ama unutulmayacak işler

**U2 teslim kaydı — 19.11.2026:** U2 kullanıcı onayıyla gerçek U1 API'sine
bağlandı; yeni endpoint/DTO/model/migration yok. 29 görev React/DTO testi dahil
tam web koşusu 282 başarılı / 3 opt-in atlandı; gerçek HTTPS+ayrı PostgreSQL
görev canlı testi ayrıca geçti. İlgili görev/izin/ilişki API testleri 49/49;
web build/lint ve backend build başarılı. Webden atama→danışan API oturumuyla
tamamlama→webden güncel durum/geçmiş okuma, 409, düzenleme/iptal, izin geri
çekme ve ilişki sonu canlı ağ üzerinden doğrulandı. Bu React DOM testidir,
tarayıcı görsel veya Flutter testi değildir. PR hazırlığında Flutter M2 d14576f
ile ortak main'den alındı; Flutter testi yapılmadı. ClientTasksEnabled varsayılan
false korunur. U3 başlatılmadı, uygulama DB migration'ı yapılmadı.

- `water_logs` izninin mobil/web/API uçtan uca doğrulanması (**M4 + U4**).
- Flutter ve React parola sıfırlama ekranlarının gerçek API'ye bağlanması (**M5 + U5**); şifre sıfırlama backend'i daha önce tamamlandı.
- Gerçek kullanıcı ekranlarında sentetik veri olmaması, yüklenme/boş/hata durumlarının ayrılması (**M6 + U6**).
- Android emülatörü ve mümkünse iOS cihazı ile sağlık izinleri, React tarayıcı testi, karşılıklı veri paylaşımı ve revocation testi (**M6 + U6**).
- Kapsamlı Admin/Audit Log ve daha sonraki AI yemek tanıma, besin kataloğu, tahlil OCR/PDF işlerinin **bu toplantıdaki iki çekirdek modülle karıştırılmaması**; sonraki iş listesinde tutulması.

## 6. Paralel çalışma ve entegrasyon kapıları

| Kapı | Mert | Uğur | Bir sonraki aşamaya geçiş koşulu |
|---|---|---|---|
| **A — İlk paralel çalışma** | **M1**: Flutter sağlık izin/okuma (backend yok) | **U1**: Görev backend + migration + sözleşme | U1 testleri geçti, API DTO'ları paylaşıldı ve kod ortak dala birleştirildi |
| **B — Görevlerin UI entegrasyonu** | **M2**: Flutter görev ekranları | **U2**: React görev ekranları | Webden görev ata → Flutter'da gör/tamamla → web durumunu gör testi |
| **C — Sağlık API'si** | M1'i tamamla; M3'e hazırlık | **U3**: Sağlık backend + migration | API sözleşmesi onaylı; U3 kodu ve migration ortak dala alındı |
| **D — Sağlık + su paylaşımı** | **M3**: Senkronizasyon, ardından **M4** | **U4**: Su paylaşımı backend/web | Gerçek sağlık okuma ve su izin/iptal senaryoları ayrı ayrı geçti |
| **E — Kalan istemci işleri** | **M5**: Flutter parola sıfırlama | **U5**: React parola sıfırlama | Her iki istemci gerçek reset backend'iyle test edildi |
| **F — Kapanış** | **M6**: Mobil prova | **U6**: Web/backend prova | Açık engeller ve doğrulanamayan platformlar raporlandı |

**Paralellik notu:** U2 React ekranları geliştirilirken M2 Flutter ekranları aynı anda yapılabilir; ikisi de U1'in **birleştirilmiş** API sözleşmesine dayanmalıdır. U3 ve U4 backend migration çalışmaları Uğur tarafından **sıralı** yürütülür.

## 7. Git / migration güvenlik protokolü

1. İki geliştirici de işe başlarken `git status`, `git branch --show-current`, `git log -5 --oneline` ve ilgili dosyalarda son değişiklikleri kontrol eder. Kirli çalışma ağacını ezmez.
2. **Ayrı feature branch** kullanılır (örnek: `feature/mobile-health-connect`, `feature/client-tasks-api`). İki kişi aynı dalda eş zamanlı değişiklik yapmaz. Branch açma ve Git işlemlerini geliştirici yapar, Codex değil.
3. İlk olarak bu dosya **ortak dala alınır** ve her iki kişi güncel kopyasına sahip olur. Dosyanın değişiklikleri tek kişi (Uğur) tarafından yapılır; Mert yeni kararları yazılı iletir.
4. `AppDbContext`, `Program.cs`, EF migration ve snapshot'ları **yalnız Uğur** düzenler. Aynı anda iki migration oluşturulmaz; migration geçmişi ve uygulanmış yerel DB sürümü birleştirme öncesi kontrol edilir.
5. Uğur API değiştirdiğinde Mert'e şu bilgileri gönderir: **commit/PR, endpointler, DTO örnekleri, kimlik/yetki, durum kodları, migration adı, test sonucu, açık kararlar**. Mert kendi çalışma dalını güvenle güncelleyip sonra mobil entegrasyona başlar.
6. Migration uygulamasından önce doğrulanabilir yedek alınır; mevcut demo ve gerçek kayıtlar silinmez. Codex'ten uygulama DB'sine migration yapması **ayrıca görev kapsamında** istenir.
7. Çakışma saptanırsa otomatik merge, dosya silme, migration yeniden adlandırma veya reset yapılmaz. İki varyantın farkı ve hangilerinin DB'ye uygulandığı raporlanıp karar beklenir.
8. Her görev sonunda `git diff --check`, ilgili build/test/lint, **değişen dosyalar** ve **Türkçe önerilen commit mesajı** raporlanır. Codex kendi başına commit/push/merge yapmaz; Computer Use kullanmaz.

## 8. Tamamlanma kriterleri

- **Görev takibi:** Diyetisyen React'te görev atar → danışan Flutter'da görür/durumu değiştirir → diyetisyen webde güncel durumu görür; farklı danışan/rol erişimi engellenir.
- **Sağlık senkronizasyonu:** Kullanıcı izin verir → desteklenen Health Connect/HealthKit verileri okunur → gerçek veriler API'de güvenle kalıcı saklanır → mobilde görülür; izin reddi/veri yok/tekrar okuma doğru yönetilir. Android ve iOS doğrulama durumu **ayrı** raporlanır.
- **Su paylaşımı:** Danışan bağımsız izni verir → diyetisyen gerçek su kayıtlarını webden görür → izin geri alınca yeni okumalar reddedilir; diğer izinler etkilenmez.
- **Parola sıfırlama:** Mobil ve web ekranlarından gerçek reset → yeni parola ile giriş → eski oturumların reddi; Admin MFA korunur.
- **Genel kalite:** Demo/sentetik veriler gerçek hesap ekranlarına sızmaz; en az bir gerçek UI + HTTPS/PostgreSQL uçtan uca test yapılır. Test edilemeyen iş **tamamlandı** diye raporlanmaz.

## 9. Her iki Codex için zorunlu başlangıç talimatı

> **Her yeni görevin ilk satırında kullanılabilir:**  
> `Önce AGENTS.md, docs/PARALLEL_WORK_PLAN_2026-11-19.md, ilgili güncel docs sözleşmeleri ve mevcut Git/kod durumunu incele. Bu plandaki bana ait görev ID'si ve dosya sahipliği sınırlarına uy. Başkasının dosyalarına dokunma, tamamlanmış işleri yeniden yazma; API/migration çakışmasında durup farkları raporla. Yalnız istenen tek görevi uygula. Computer Use, git pull/commit/push/merge yapma. Testleri çalıştır, kısa Türkçe rapor ve Türkçe commit mesajı öner; commit atma.`

**Mert'in Codex'i** için her promptta görev ID'si `M1`–`M6`; **Uğur'un Codex'i** için `U1`–`U6` açıkça yazılmalıdır. İstenen iş listede yoksa **önce bu belge üzerindeki sorumluluk paylaşımı kararlaştırılmalıdır**.

---

**Değişiklik kontrolü:** Bu planı güncelledikten sonra her iki geliştirici de aynı commit sürümünü kullanmalı; yalnız bir bilgisayardaki düzenleme diğer Codex tarafından kendiliğinden görülmez.
