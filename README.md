# Smart Nutrition Platform

**Yapay Zekâ Destekli Akıllı Beslenme ve Diyetisyen Platformu**

Diyetisyen odaklı, danışanlar için mobil uygulama ve diyetisyenler için web yönetim paneli sunması hedeflenen **sıfırdan geliştirilecek** ürün. Üniversite bitirme projesi olarak başlayacak; güvenlik, kullanılabilirlik ve dağıtım gereksinimleri karşılandığında mağazada yayımlanabilir ve ticari olarak sunulabilir bir temele sahip olması amaçlanır.

## Amaçlanan başlıca işlevler
- Danışan: öğün/besin, kalori/makro, su, kilo/ölçüm, aktivite ve tahlil takibi; kişisel hedef/program veya atanmış program. Kişisel öneriler düzenlenebilir, diyetisyen programı/hedefleri salt okunurdur; gerçek tüketim serbestçe kaydedilir.
- Diyetisyen: mobil/web başvuru ve Admin doğrulaması; arama/davet kodu ve karşılıklı onayla bağlantı. En fazla bir aktif diyetisyen ve kişisel/atanmış toplamında tek aktif `NutritionPlan`; geçmiş ve öğün alternatifleri korunur.
- Takip: izinli danışan yönetimi, öğün yorumları/cevaplar/bildirimler, görev/son tarih/durum ve isteğe bağlı hatırlatmalar, grafik/program uyumu/PDF raporları. Hibrit besin kataloğu ve özel tarifler desteklenir.
- Yapay zekâ: fotoğraf/galeriden **tahmini** kalori/makro; kullanıcı kontrol/onayı olmadan öğün oluşmaz. Tahlilde manuel giriş ve referans değerlendirmesinin ardından kullanıcı onaylı PDF/fotoğraf OCR; doğrulanabilir ML opsiyoneldir.
- Entegrasyon: ayrı izinle Health Connect/HealthKit üzerinden adım, mesafe, egzersiz, süre, aktif kalori ve nabız; manuel giriş, kaynak ve tekilleştirme.
- Güvenlik/deneyim: kategori bazlı paylaşım, tahlil için ayrıca açık onay, güvenli e-posta/şifre oturumu ve zorunlu Admin MFA; sağlık verisine varsayılan Admin erişimi yoktur. Premium UI/UX, ortak tokenlar ve açık/koyu tema.

İlk sürüm yönetim paneli webdedir; öğün yorumları, cevaplar ve bildirimler ilk sürüm koşuludur. Diğer onaylı özelliklerin takvimi, sonraya bırakılan sohbet/sürekli kamera ve opsiyonel araştırma ayrımı [proje kapsamında](docs/01_PROJECT_SCOPE.md) açıklanır; tüm özellikler aynı MVP'ye vaat edilmez.

> Sağlık uyarısı: Sistem teşhis koymaz, tedavi/ilaç önermez; görselden kalori hesabı kesin ölçüm değildir. Sağlık verileri özel niteliklidir ve korunmalıdır.

## Durum
`DOCS-V1` — **22 ürün/teknoloji kararı onaylıdır; başlangıç uygulamaları ve web/Auth akışı mevcuttur.** Backend'de danışan kaydı, e-posta doğrulama/yeniden gönderme, 15 dakikalık JWT giriş, kendi hesap özeti ve W2 web cookie/CSRF/çıkış uygulanmıştır. B1–B3 ortak onayıyla ayrı diyetisyen başvurusu, başvuru durumu, TOTP/kurtarma kodlu Admin web girişi ve audit'li uzman onayı gerçek API'lere bağlıdır. R1–R3 ile gerçek çalışma alanı, davet/karşılıklı onay, aktif danışanların sınırlı listesi/detayı ve varsayılan kapalı program paylaşımı eklenmiştir. Sağlık kayıt ekranları ayrı sentetik önizlemedir; program oluşturma/atama henüz uygulanmamıştır. Bu durum canlı yayın veya tüm 29 Ekim aşamasının tamamlandığı anlamına gelmez.

**29 Ekim önceliği — Uğur alanı:** Sıradaki parça program oluşturma/atamadır. Flutter/Mert dosyaları bu çalışmanın kapsamı dışındadır. Açık teknik kararlar [12](docs/12_TEAM_PLAN_AND_DECISIONS.md), B1–B3 ortak onayı [14](docs/14_OCTOBER_PRESENTATION_CONTRACT_PROPOSAL.md), R1–R3 ortak onayı [15](docs/15_RELATIONSHIP_CONTRACT_PROPOSAL.md) içinde izlenir. Mevcut danışan register/JWT gövdeleri korunur; entegrasyondan önce iki taraf ortak main sürümünü çeker.

## Mevcut repo düzeni
```text
smart-nutrition-platform/
├── AGENTS.md
├── README.md
├── docs/
├── apps/web/        # React + TypeScript
├── backend/         # ASP.NET Core / C#, PostgreSQL ve testler
└── mobile/          # Flutter / Dart; Mert'in alanı
```
Çalıştırma ve doğrulama adımları [web](apps/web/README.md), [backend](backend/README.md) ve [mobil](mobile/README.md) belgelerindedir. Ayrı AI servisi henüz yoktur; ihtiyaç olduğunda Python/FastAPI kullanılması onaylıdır. Yeni paketler/klasörler ihtiyaç oldukça eklenir; feature-based yapı korunur.

## İki geliştiricili çalışma
1. Her geliştirici önce kökteki [`AGENTS.md`](AGENTS.md) dosyasını okur.
2. **Aynı isimler** için [`docs/04_NAMING_CONVENTIONS.md`](docs/04_NAMING_CONVENTIONS.md), **aynı veri şeması** için [`docs/05_DATA_DICTIONARY.md`](docs/05_DATA_DICTIONARY.md), **aynı API** için [`docs/06_API_CONTRACT.md`](docs/06_API_CONTRACT.md) temel alınır.
3. Ortak uzak depo `mertaliserbet/smart-nutrition-platform`, entegrasyon dalı `main`dir. 28.10.2026 kullanıcı kararıyla her yeni iş güncel ortak `main`den açılan görev/feature branch'inde yapılır ve ortak `main`e PR oluşturulur. Bu checkout'ta ortak depo `upstream`, kişisel fork `origin`dir; görev branch'i fork'a push edilir. Kullanıcı açıkça istemedikçe `main`e doğrudan push yapılmaz.
4. Görevler küçük commitlere bölünür; değişiklik özeti + test sonucu verilir. Görev ve push/PR öncesi ortak `main` kontrol edilir; aynı dosyaya paralel yazılmaz, force push yapılmaz. Ayrıntılar [`ekip planında`](docs/12_TEAM_PLAN_AND_DECISIONS.md) yer alır.
5. Sözleşme değişikliği iki geliştirici tarafından onaylanır ve tek ortak commit ile gerçekleştirilir. Mevcut PR'ları birleştirme/kapatma ve eski dalları silme ayrıca açık kullanıcı talimatı gerektirir.
6. Dal, commit/PR başlığı, dosya, klasör ve modül adlarında geliştirme aracının adı kullanılmaz; amaç ve proje kavramları esas alınır.

Mert mobil ve ilgili API'ler; Uğur web, Auth ve ilgili API'ler; AI ortak sorumluluğundadır. Ayrıntılı modül liderliği `12`de teyit edilir. `04/05/06`daki açık parçalar için her istemci ayrı DTO/endpoint üretmez; ilgili geliştirme öncesi ortak onay gerekir.

## Dokümantasyon
| Belge | Konu |
|---|---|
| [01](docs/01_PROJECT_SCOPE.md) | Ürün kapsamı ve özellik öncelikleri |
| [02](docs/02_ROLES_AND_WORKFLOWS.md) | Roller, kullanıcı akışları, diyetisyen süreçleri |
| [03](docs/03_SYSTEM_ARCHITECTURE.md) | Sistem bileşenleri, onaylı teknolojiler ve açık mimari ayrıntılar |
| [04](docs/04_NAMING_CONVENTIONS.md) | **Kanonik isimlendirme kuralları** |
| [05](docs/05_DATA_DICTIONARY.md) | **Entity ve alan sözlüğü** |
| [06](docs/06_API_CONTRACT.md) | **Ortak HTTP/JSON API sözleşmesi** |
| [07](docs/07_MOBILE_SPEC.md) | Danışan mobil uygulaması |
| [08](docs/08_WEB_SPEC.md) | Diyetisyen ve admin web paneli |
| [09](docs/09_DESIGN_SYSTEM.md) | Premium UI/UX kuralları |
| [10](docs/10_AI_SPEC.md) | Besin görseli ve laboratuvar analizi |
| [11](docs/11_SECURITY_AND_RELEASE.md) | KVKK, test, kalite ve yayın öncesi kontroller |
| [12](docs/12_TEAM_PLAN_AND_DECISIONS.md) | Görev sahipliği, yol haritası, karar kaydı |

**Geliştirme ilkesi:** Hedef gerçek ürün kalitesi olsa da tüm özelliklerin ilk sunuma yetiştiği varsayılmaz. MVP ve araştırma özellikleri ayrıdır.
