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
        "Tünel/sinyal kaybı olan trip'te rota kırık kalır (kuş uçuşu yok)"
    ]
}
