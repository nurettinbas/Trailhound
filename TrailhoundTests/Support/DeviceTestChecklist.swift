import Foundation

/// Manual device test checklist — run on a real phone after each release candidate.
enum DeviceTestChecklist {
    static let items = [
        "30+ dk gerçek sürüş: km ve süre akıyor",
        "Arka plana at, 5 dk bekle: kayıt devam ediyor",
        "Kısayollar: araca bağlanınca kayıt başlar",
        "Kısayollar: araçtan ayrılınca kayıt durur",
        "Uygulamayı öldür → aç → orphan banner / recovery",
        "Detay haritada rota gerçekçi (denizden geçmiyor)",
        "Pairing: araç adı yazarken klavye akıcı",
        "Kayıt sırasında Trips dışı sekmeye geçince kasma azalır",
        "Uzun trip detay açılışı donmadan yüklenir",
        "50 km trip detay: DevLog points/displayPts/colorSegs; colorSegs ≤ 60",
        "500 km trip detay (varsa): açılış akıcı, virajlar düzleşmemiş",
        "Aynı uzun trip'e ikinci giriş anında (memory cache)",
        "App kill → aç → uzun trip detay hâlâ hızlı (disk cache)",
        "GPS trim sonrası harita güncellenir (cache invalidation)",
        "Merge sonrası birleşik rota doğru çizilir",
        "Tünel/sinyal kaybı olan trip'te rota kırık kalır (kuş uçuşu yok)",
        "Start yanı Select: sadece foto/simge + chevron; isim yazısı yok, taşma yok",
        "Kayıt kartı: araç foto büyük, Stop’ta stop.fill ikonu",
        "Vespa / motorsiklet / araba işaretleri yolda sağa bakıyor",
        "Dynamic Island + kilit banner: araç foto veya doğru SF; yön sağa",
        "Bildirimler: canlı kayıt kartı road + foto + kontroller",
        "Pause/resume: road remount yok; Island foto kaybolmuyor",
        "Home-screen widget: Pause → Resume etiketi değişir; Resume → Pause geri gelir",
        "Kilit banner pause/resume: ikon+renk anında; widget da Resume’a geçer",
        "Fotolu araçla kayıt: Island’da foto çıkar; DevLog ‘photo attached (N B)’",
        "Beyaz/açık renkli araç fotosu: punch sonrası foto kayboluyorsa orijinal foto gösterilir",
        "Fotosuz araç: Island + bildirim kartı SF simgeye düşer, boş kalmaz",
        "Island genişletilmiş: üstte boşluk yok, alt butonlar kesilmiyor (1:00:10 süreyle de)",
        "Araç seçim menüsü: satır ikonları sağa bakıyor, seçilide tik kalıyor",
        "Araç foto: Add → Library/Camera seçici; Library/Camera’da tek sheet expand (~%72), kapanıp açılma yok",
        "Araç foto: Capture Geri → seçiciye küçülür; Cancel seçicide sheet’i kapatır",
        "Araç foto: All Photos sistem picker; seçince framing",
        "Araç foto: kamera shutter; arka plana atınca yeşil nokta kapanır",
        "Araç foto: limited library / deny photos / deny camera durumları",
        "Araç foto: Change + mevcut framing Apply/Save yolu bozulmaz"
    ]
}
