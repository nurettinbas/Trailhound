# TestFlight ve App Store yayın kontrol listesi

## Ön koşullar

- Apple Developer Program üyeliği
- Uygulama ikonu (1024x1024)
- Gizlilik politikası URL'si (konum verisi cihazda kalır)

## Otomatik testler (CI / lokal)

- [ ] `./scripts/run_tests.sh` yeşil (unit + UI smoke)
- [ ] GitHub Actions `iOS Tests` workflow yeşil

## Xcode hazırlığı

1. Bundle ID: `com.trailhound.app`
2. Widget: `com.trailhound.app.widget`
3. Signing: Automatic + Team seç
4. Capabilities: App Groups, Background Modes (location)

## App Store Connect

1. Yeni uygulama oluştur
2. Gizlilik manifest: `PrivacyInfo.xcprivacy` dahil
3. Konum kullanım açıklaması: yolculuk kaydı
4. Ekran görüntüleri: liste, detay harita, istatistik, ayarlar

## TestFlight

1. Archive → Distribute → App Store Connect
2. Internal testing grubu
3. Aşağıdaki **fiziksel cihaz** checklist'ini tamamla (CI'da otomatiklenemez)

## Fiziksel cihaz test checklist

Bu maddeler `DeviceTestChecklist` enum'unda kod olarak da korunur (`DeviceTestChecklistTests`).

- [ ] **30+ dk gerçek sürüş** — km ve süre akıyor
- [ ] **Arka plan** — uygulamayı arka plana at, 5 dk bekle: kayıt devam ediyor
- [ ] **Kısayollar auto-start** — araca bağlanınca (Bluetooth / CarPlay / Wi‑Fi otomasyonu) kayıt başlar
- [ ] **Kısayollar auto-stop** — araçtan ayrılınca kayıt durur
- [ ] **Orphan recovery** — uygulamayı öldür → aç → orphan banner / recovery
- [ ] **Harita** — detay haritada rota gerçekçi (denizden geçmiyor)

Ek smoke (opsiyonel):

- [ ] **Manuel kayıt** — uygulama içinden başlat / duraklat / bitir
- [ ] **Widget / Siri** — widget veya Siri kısayolu ile kayıt başlatma / durdurma
- [ ] **Export** — JSON, CSV, GPX veya KML dışa aktarma

## Araç bakım & masraf (V13)

- [ ] **Schema upgrade** — mevcut store ile açılış; trip/araç kaybı yok
- [ ] **Vade ekle** — bakım (30/7/1), sigorta/kasko (7/1) hatırlatmaları planlanır
- [ ] **Overdue banner** — Trips üstünde kırmızı uyarı; dismiss ertesi güne kadar
- [ ] **Masraf ekle** — tutar + kategori; Stats → Araç maliyetleri grafiği güncellenir
- [ ] **Araç sil** — schedule/expense cascade + care bildirimleri iptal
- [ ] **Kayıt scroll** — aktif trip varken Trips kaydırma akıcı (banner regression yok)

## Kısayollar ile otomatik kayıt

- Otomatik başlat/bitir **Shortcuts Personal Automations** ile kurulur (Pairing sekmesindeki rehber).
- Uygulama içi Bluetooth ses-rotası eşleştirmesi kaldırıldı; ekstra Bluetooth entitlement gerekmez.
- Konum + arka plan konum modu yalnızca aktif kayıt için kullanılır.

## Release sırası (özet)

1. Otomatik testler yeşil
2. TestFlight internal build yükle
3. Fiziksel cihaz checklist (6 madde)
4. Archive → App Store Connect
