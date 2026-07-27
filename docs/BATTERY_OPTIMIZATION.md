# Pil optimizasyonu notları

## Uygulanan stratejiler

1. **Idle:** Kayıt yokken `LocationService` kapalı (Shortcuts otomasyonu uygulama içinde sürekli GPS dinlemez).
2. **Kayıt sırasında:** `startTracking()` — navigasyon doğruluğu, 5 m filtre.
3. **Geocoding:** Yalnızca trip başlangıç/bitişinde; offline'da pending, ağ gelince retry.
4. **Polyline:** 1000+ noktada Douglas-Peucker sadeleştirme.
5. **Timer:** Yalnızca aktif kayıtta 1 sn elapsed timer.
6. **Kayıt animasyonu:** Düşük güç modunda 15 FPS; `reduceMotion` desteklenir.

## Instruments ile doğrulama

1. Gerçek iPhone bağla.
2. Xcode → Product → Profile → Energy Log.
3. Senaryolar: 30 dk sürüş kaydı, arka plan, Shortcuts ile başlat/bitir.
4. Hedef: kayıt dışında Location Services sürekli aktif olmamalı.

## Arka plan görev denetimi

- Otomatik başlat/bitir: **Shortcuts Personal Automations** (Bluetooth / CarPlay / Wi‑Fi). Uygulama içi Bluetooth ses-rotası dinleyicisi yok.
- Live Activity: yalnızca kayıt sırasında.

## TestFlight öncesi kontrol listesi

- [ ] 2+ saat gerçek sürüşte pil tüketimi kabul edilebilir
- [ ] Kayıt bitince GPS duruyor
- [ ] Kısayollar otomasyonu: araca bağlanınca kayıt başlıyor, ayrılınca duruyor
- [ ] Kayıt yokken arka planda sürekli GPS çekilmiyor
