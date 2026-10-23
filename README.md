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
`DOCS-V1` — **22 ürün/teknoloji kararı onaylıdır; uygulama kodu hazır değildir.** Ortak sözleşmelerde Auth/izin, program sürümü ve diğer özellik DTO'ları için açık parçalar vardır. Belgelerin güncellenmesi uygulama, test veya canlı yayın onayı değildir. Neye başlanabileceği ve hangi kararların entegrasyonu engellediği [12 — Geliştirmeye hazırlık ve sözleşme bulguları](docs/12_TEAM_PLAN_AND_DECISIONS.md#geliştirmeye-hazırlık-ve-sözleşme-bulguları) bölümünde izlenir.

## Önerilen repo düzeni (henüz oluşturulmuş değildir)
```text
smart-nutrition-platform/
├── AGENTS.md
├── README.md
├── docs/
├── apps/
│   ├── mobile/      # Flutter / Dart
│   └── web/         # React + TypeScript
└── services/
    ├── api/         # ASP.NET Core / C# + PostgreSQL
    └── ai/          # Python / FastAPI (gerektiğinde)
```
Teknoloji seçimi onaylıdır; gösterilen klasör düzeni bir yerleşim planıdır, oluşturulmuş uygulama değildir. İskelet ayrı uygulama görevi kapsamında, ilgili sözleşme sınırları gözetilerek kurulur. Yeni paketler/klasörler ihtiyaç oldukça eklenir; feature-based yapı korunur, gereksiz katman açılmaz.

## Codex ile iki geliştiricili çalışma
1. Her geliştirici önce kökteki [`AGENTS.md`](AGENTS.md) dosyasını okur.
2. **Aynı isimler** için [`docs/04_NAMING_CONVENTIONS.md`](docs/04_NAMING_CONVENTIONS.md), **aynı veri şeması** için [`docs/05_DATA_DICTIONARY.md`](docs/05_DATA_DICTIONARY.md), **aynı API** için [`docs/06_API_CONTRACT.md`](docs/06_API_CONTRACT.md) temel alınır.
3. Görevler küçük PR/commitlere bölünür; Codex değişiklik özeti + test sonucu verir.
4. Sözleşme değişikliği iki geliştirici tarafından onaylanır ve tek ortak commit/PR ile gerçekleştirilir.

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
