# Smart Nutrition Platform

**Yapay Zekâ Destekli Akıllı Beslenme ve Diyetisyen Platformu**

Diyetisyen odaklı, danışanlar için mobil uygulama ve diyetisyenler için web yönetim paneli sunması hedeflenen **sıfırdan geliştirilecek** ürün. Üniversite bitirme projesi olarak başlayacak; güvenlik, kullanılabilirlik ve dağıtım gereksinimleri karşılandığında mağazada yayımlanabilir ve ticari olarak sunulabilir bir temele sahip olması amaçlanır.

## Amaçlanan başlıca işlevler
- Danışan: öğün/besin, kalori/makro, su, kilo/ölçüm, beslenmeyle ilişkili aktivite takibi; beslenme planına erişim.
- Diyetisyen: danışan yönetimi, bireysel beslenme planı oluşturma/atama, kayıt ve gelişim izleme.
- Yapay zekâ: fotoğrafla besin tespiti ve **tahmini** kalori/makro; laboratuvar sonuçlarını referans aralığı temelinde **açıklayıcı** değerlendirme.
- Entegrasyon: kullanıcı onayıyla uygun cihaz/sağlık platformundan aktivite verileri.

> Sağlık uyarısı: Sistem teşhis koymaz, tedavi/ilaç önermez; görselden kalori hesabı kesin ölçüm değildir. Sağlık verileri özel niteliklidir ve korunmalıdır.

## Durum
`DOCS-V1` — dokümantasyon / ürün-mimari kararları netleştirme. **Henüz uygulama kodu hazır değildir.** Ürün ve teknoloji seçenekleri `docs/12_TEAM_PLAN_AND_DECISIONS.md` onaylandıkça geliştirme başlar.

## Önerilen repo düzeni (henüz oluşturulmuş değildir)
```text
smart-nutrition-platform/
├── AGENTS.md
├── README.md
├── docs/
├── apps/
│   ├── mobile/      # öneri: Flutter
│   └── web/         # öneri: React + TypeScript
└── services/
    ├── api/         # öneri: ASP.NET Core
    └── ai/          # öneri: Python / FastAPI (gerektiğinde)
```
Repo iskeleti yalnızca teknoloji kararı onaylanınca oluşturulmalıdır. Yeni paketler/klasörler ihtiyaç oldukça eklenir; gereksiz katman açılmaz.

## Codex ile iki geliştiricili çalışma
1. Her geliştirici önce kökteki [`AGENTS.md`](AGENTS.md) dosyasını okur.
2. **Aynı isimler** için [`docs/04_NAMING_CONVENTIONS.md`](docs/04_NAMING_CONVENTIONS.md), **aynı veri şeması** için [`docs/05_DATA_DICTIONARY.md`](docs/05_DATA_DICTIONARY.md), **aynı API** için [`docs/06_API_CONTRACT.md`](docs/06_API_CONTRACT.md) temel alınır.
3. Görevler küçük PR/commitlere bölünür; Codex değişiklik özeti + test sonucu verir.
4. Sözleşme değişikliği iki geliştirici tarafından onaylanır ve tek ortak commit/PR ile gerçekleştirilir.

## Dokümantasyon
| Belge | Konu |
|---|---|
| [01](docs/01_PROJECT_SCOPE.md) | Ürün kapsamı ve özellik öncelikleri |
| [02](docs/02_ROLES_AND_WORKFLOWS.md) | Roller, kullanıcı akışları, diyetisyen süreçleri |
| [03](docs/03_SYSTEM_ARCHITECTURE.md) | Sistem bileşenleri, olası teknoloji seçimi |
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
