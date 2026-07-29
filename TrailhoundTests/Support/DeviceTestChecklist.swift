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
        "Uzun trip detay açılışı donmadan yüklenir"
    ]
}
