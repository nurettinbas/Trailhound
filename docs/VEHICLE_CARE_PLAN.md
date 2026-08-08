# Araç masraf & bakım takibi

> **Durum:** Uygulandı (schema V13) + UI ayrımı revizyonu  
> **Yerleşim:** Araçlar sekmesi → tek detay ekranı

---

## İki katman (karıştırmayın)

| Katman | Ne için | UI |
|--------|---------|-----|
| **Takip & hatırlatmalar** | Vize, sigorta, kasko, bakım vadeleri + push | `VehicleSchedule` |
| **Harcamalar** | Ödenen tutar kaydı (ayrı) | `VehicleExpense` |

Hatırlatma eklemek harcama eklemek değildir. “Yaptırdım” takip section’ında vade kapatır ve isteğe bağlı masraf yazar; “Harcama ekle” yalnızca gider kaydıdır.

---

## Tek ekran sırası

1. **Araç bilgileri** — profil draft + Kaydet (`PairingVehicleEditorForm` embedded)
2. **Takip & hatırlatmalar** — vadeler, Hatırlatma ekle, Yaptırdım
3. **Harcamalar** — liste + Harcama ekle

Maliyet grafikleri yalnızca **Stats** sekmesinde (`VehicleCostSnapshotLoader` / Araç maliyetleri).

---

## Harcama kategorileri (picker)

Yakıt · Kasko · Bakım · Vize · Arıza · Aksesuar · Diğer

Eski raw (`insurance`, `tax`, `parking`, `parts`) okumada map edilir; schema bump yok.

---

## Bildirimler

- Bakım / muayene: 30 / 7 / 1 gün kala  
- Sigorta / kasko: 7 / 1 gün kala  
- Overdue: in-app banner (kırmızı); push spam yok  

---

## Performans

- Profil: draft + Save  
- Due: `VehicleCareSummaryStore`  
- Mini chart: 120 ms debounce, trip points fault yok  
- Glass / brand renkleri; rainbow chart yok  
