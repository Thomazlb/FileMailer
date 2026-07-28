#!/usr/bin/env python3

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "App/Resources/Localizable.xcstrings"
RESOURCES = ROOT / "FinderExtension/Resources"

TRANSLATIONS = {
    "ar": ["إرسال بالبريد الإلكتروني", "إرسال هذا المجلد بالبريد الإلكتروني", "جارٍ التحضير باستخدام Apple Intelligence…", "تحضير الرسالة", "جارٍ تحضير الرسالة…"],
    "bn": ["ই-মেইলে পাঠান", "এই ফোল্ডারটি ই-মেইলে পাঠান", "Apple Intelligence দিয়ে প্রস্তুত করা হচ্ছে…", "বার্তা প্রস্তুত করা হচ্ছে", "বার্তা প্রস্তুত করা হচ্ছে…"],
    "ca": ["Envia per correu electrònic", "Envia aquesta carpeta per correu electrònic", "S’està preparant amb Apple Intelligence…", "Preparació del missatge", "S’està preparant el missatge…"],
    "cs": ["Odeslat e-mailem", "Odeslat tuto složku e-mailem", "Příprava pomocí Apple Intelligence…", "Příprava zprávy", "Připravuje se zpráva…"],
    "da": ["Send via e-mail", "Send denne mappe via e-mail", "Forbereder med Apple Intelligence…", "Forbereder besked", "Forbereder besked…"],
    "de": ["Per E-Mail senden", "Diesen Ordner per E-Mail senden", "Mit Apple Intelligence vorbereiten…", "Nachricht vorbereiten", "Nachricht wird vorbereitet…"],
    "el": ["Αποστολή μέσω email", "Αποστολή αυτού του φακέλου μέσω email", "Προετοιμασία με το Apple Intelligence…", "Προετοιμασία μηνύματος", "Γίνεται προετοιμασία του μηνύματος…"],
    "en": ["Send by Email", "Email This Folder", "Preparing with Apple Intelligence…", "Preparing Message", "Preparing Message…"],
    "en-AU": ["Send by Email", "Email This Folder", "Preparing with Apple Intelligence…", "Preparing Message", "Preparing Message…"],
    "en-CA": ["Send by Email", "Email This Folder", "Preparing with Apple Intelligence…", "Preparing Message", "Preparing Message…"],
    "en-GB": ["Send by Email", "Email This Folder", "Preparing with Apple Intelligence…", "Preparing Message", "Preparing Message…"],
    "es": ["Enviar por correo electrónico", "Enviar esta carpeta por correo electrónico", "Preparando con Apple Intelligence…", "Preparación del mensaje", "Preparando el mensaje…"],
    "es-MX": ["Enviar por correo electrónico", "Enviar esta carpeta por correo electrónico", "Preparando con Apple Intelligence…", "Preparación del mensaje", "Preparando el mensaje…"],
    "fi": ["Lähetä sähköpostilla", "Lähetä tämä kansio sähköpostilla", "Valmistellaan Apple Intelligencen avulla…", "Valmistellaan viestiä", "Viestiä valmistellaan…"],
    "fr": ["Envoyer par e-mail", "Envoyer ce dossier par e-mail", "Préparation avec Apple Intelligence…", "Préparation du message", "Préparation du message…"],
    "fr-CA": ["Envoyer par courriel", "Envoyer ce dossier par courriel", "Préparation avec Apple Intelligence…", "Préparation du message", "Préparation du message…"],
    "gu": ["ઇમેઇલ દ્વારા મોકલો", "આ ફોલ્ડર ઇમેઇલ દ્વારા મોકલો", "Apple Intelligence વડે તૈયાર થઈ રહ્યું છે…", "સંદેશ તૈયાર થઈ રહ્યો છે", "સંદેશ તૈયાર થઈ રહ્યો છે…"],
    "he": ["שליחה בדוא״ל", "שליחת תיקייה זו בדוא״ל", "הכנה באמצעות Apple Intelligence…", "הכנת ההודעה", "ההודעה בהכנה…"],
    "hi": ["ईमेल से भेजें", "इस फ़ोल्डर को ईमेल से भेजें", "Apple Intelligence से तैयार किया जा रहा है…", "संदेश तैयार किया जा रहा है", "संदेश तैयार किया जा रहा है…"],
    "hr": ["Pošalji e-mailom", "Pošalji ovu mapu e-mailom", "Priprema uz Apple Intelligence…", "Priprema poruke", "Poruka se priprema…"],
    "hu": ["Küldés e-mailben", "A mappa elküldése e-mailben", "Előkészítés az Apple Intelligence segítségével…", "Üzenet előkészítése", "Az üzenet előkészítése…"],
    "id": ["Kirim melalui Email", "Kirim Folder Ini melalui Email", "Menyiapkan dengan Apple Intelligence…", "Menyiapkan Pesan", "Pesan sedang disiapkan…"],
    "it": ["Invia tramite email", "Invia questa cartella tramite email", "Preparazione con Apple Intelligence…", "Preparazione del messaggio", "Preparazione del messaggio…"],
    "ja": ["メールで送信", "このフォルダをメールで送信", "Apple Intelligenceで準備中…", "メッセージを準備中", "メッセージを準備中…"],
    "kn": ["ಇಮೇಲ್ ಮೂಲಕ ಕಳುಹಿಸಿ", "ಈ ಫೋಲ್ಡರ್ ಅನ್ನು ಇಮೇಲ್ ಮೂಲಕ ಕಳುಹಿಸಿ", "Apple Intelligence ಮೂಲಕ ಸಿದ್ಧಪಡಿಸಲಾಗುತ್ತಿದೆ…", "ಸಂದೇಶವನ್ನು ಸಿದ್ಧಪಡಿಸಲಾಗುತ್ತಿದೆ", "ಸಂದೇಶವನ್ನು ಸಿದ್ಧಪಡಿಸಲಾಗುತ್ತಿದೆ…"],
    "ko": ["이메일로 보내기", "이 폴더를 이메일로 보내기", "Apple Intelligence로 준비 중…", "메시지 준비 중", "메시지 준비 중…"],
    "ml": ["ഇമെയിൽ വഴി അയയ്ക്കുക", "ഈ ഫോൾഡർ ഇമെയിൽ വഴി അയയ്ക്കുക", "Apple Intelligence ഉപയോഗിച്ച് തയ്യാറാക്കുന്നു…", "സന്ദേശം തയ്യാറാക്കുന്നു", "സന്ദേശം തയ്യാറാക്കുന്നു…"],
    "mr": ["ईमेलने पाठवा", "हे फोल्डर ईमेलने पाठवा", "Apple Intelligence वापरून तयार करत आहे…", "संदेश तयार करत आहे", "संदेश तयार करत आहे…"],
    "ms": ["Hantar melalui E-mel", "Hantar Folder Ini melalui E-mel", "Menyediakan dengan Apple Intelligence…", "Menyediakan Mesej", "Mesej sedang disediakan…"],
    "nl": ["Verstuur per e-mail", "Verstuur deze map per e-mail", "Voorbereiden met Apple Intelligence…", "Bericht voorbereiden", "Bericht wordt voorbereid…"],
    "no": ["Send med e-post", "Send denne mappen med e-post", "Forbereder med Apple Intelligence…", "Forbereder melding", "Forbereder melding…"],
    "or": ["ଇମେଲ୍ ଦ୍ୱାରା ପଠାନ୍ତୁ", "ଏହି ଫୋଲ୍ଡରକୁ ଇମେଲ୍ ଦ୍ୱାରା ପଠାନ୍ତୁ", "Apple Intelligence ସହିତ ପ୍ରସ୍ତୁତ କରାଯାଉଛି…", "ସନ୍ଦେଶ ପ୍ରସ୍ତୁତ କରାଯାଉଛି", "ସନ୍ଦେଶ ପ୍ରସ୍ତୁତ କରାଯାଉଛି…"],
    "pa": ["ਈਮੇਲ ਰਾਹੀਂ ਭੇਜੋ", "ਇਸ ਫੋਲਡਰ ਨੂੰ ਈਮੇਲ ਰਾਹੀਂ ਭੇਜੋ", "Apple Intelligence ਨਾਲ ਤਿਆਰ ਕੀਤਾ ਜਾ ਰਿਹਾ ਹੈ…", "ਸੁਨੇਹਾ ਤਿਆਰ ਕੀਤਾ ਜਾ ਰਿਹਾ ਹੈ", "ਸੁਨੇਹਾ ਤਿਆਰ ਕੀਤਾ ਜਾ ਰਿਹਾ ਹੈ…"],
    "pl": ["Wyślij e-mailem", "Wyślij ten folder e-mailem", "Przygotowywanie z Apple Intelligence…", "Przygotowywanie wiadomości", "Wiadomość jest przygotowywana…"],
    "pt-BR": ["Enviar por e-mail", "Enviar esta pasta por e-mail", "Preparando com a Apple Intelligence…", "Preparando a mensagem", "Preparando a mensagem…"],
    "pt-PT": ["Enviar por e-mail", "Enviar esta pasta por e-mail", "A preparar com a Apple Intelligence…", "A preparar a mensagem", "A preparar a mensagem…"],
    "ro": ["Trimite prin e-mail", "Trimite acest dosar prin e-mail", "Se pregătește cu Apple Intelligence…", "Se pregătește mesajul", "Mesajul se pregătește…"],
    "ru": ["Отправить по электронной почте", "Отправить эту папку по электронной почте", "Подготовка с помощью Apple Intelligence…", "Подготовка сообщения", "Сообщение подготавливается…"],
    "sk": ["Odoslať e-mailom", "Odoslať tento priečinok e-mailom", "Príprava pomocou Apple Intelligence…", "Príprava správy", "Správa sa pripravuje…"],
    "sl": ["Pošlji po e-pošti", "Pošlji to mapo po e-pošti", "Priprava z Apple Intelligence…", "Priprava sporočila", "Sporočilo se pripravlja…"],
    "sv": ["Skicka via e-post", "Skicka den här mappen via e-post", "Förbereder med Apple Intelligence…", "Förbereder meddelande", "Meddelandet förbereds…"],
    "ta": ["மின்னஞ்சல் மூலம் அனுப்பவும்", "இந்தக் கோப்புறையை மின்னஞ்சல் மூலம் அனுப்பவும்", "Apple Intelligence மூலம் தயாராகிறது…", "செய்தி தயாராகிறது", "செய்தி தயாராகிறது…"],
    "te": ["ఇమెయిల్ ద్వారా పంపండి", "ఈ ఫోల్డర్‌ను ఇమెయిల్ ద్వారా పంపండి", "Apple Intelligenceతో సిద్ధం చేస్తోంది…", "సందేశాన్ని సిద్ధం చేస్తోంది", "సందేశాన్ని సిద్ధం చేస్తోంది…"],
    "th": ["ส่งทางอีเมล", "ส่งโฟลเดอร์นี้ทางอีเมล", "กำลังจัดเตรียมด้วย Apple Intelligence…", "กำลังจัดเตรียมข้อความ", "กำลังจัดเตรียมข้อความ…"],
    "tr": ["E-postayla Gönder", "Bu Klasörü E-postayla Gönder", "Apple Intelligence ile hazırlanıyor…", "Mesaj hazırlanıyor", "Mesaj hazırlanıyor…"],
    "uk": ["Надіслати електронною поштою", "Надіслати цю папку електронною поштою", "Підготовка за допомогою Apple Intelligence…", "Підготовка повідомлення", "Повідомлення готується…"],
    "ur": ["ای میل کے ذریعے بھیجیں", "اس فولڈر کو ای میل کے ذریعے بھیجیں", "Apple Intelligence کے ذریعے تیاری جاری ہے…", "پیغام تیار کیا جا رہا ہے", "پیغام تیار کیا جا رہا ہے…"],
    "vi": ["Gửi qua Email", "Gửi Thư mục này qua Email", "Đang chuẩn bị bằng Apple Intelligence…", "Đang chuẩn bị thư", "Đang chuẩn bị thư…"],
    "zh-Hans": ["通过电子邮件发送", "通过电子邮件发送此文件夹", "正在使用 Apple Intelligence 准备…", "正在准备邮件", "正在准备邮件…"],
    "zh-Hant": ["透過電子郵件傳送", "透過電子郵件傳送此檔案夾", "正在使用 Apple Intelligence 準備…", "正在準備郵件", "正在準備郵件…"],
}

KEYS = [
    "Send by Email",
    "Envoyer ce dossier par e-mail",
    "Préparation avec Apple Intelligence…",
    "Préparation du message",
    "Préparation du message…",
]


def quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def catalog_value(catalog: dict, source: str, locale: str) -> str:
    if locale == "fr":
        return source
    return catalog["strings"][source]["localizations"][locale]["stringUnit"]["value"]


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    for locale, generated in TRANSLATIONS.items():
        values = dict(zip(KEYS, generated, strict=True))
        values["Other Recipient…"] = catalog_value(catalog, "Autre destinataire…", locale)
        values["Edit Recipients…"] = catalog_value(
            catalog, "Modifier les destinataires…", locale
        )
        values["Open FileMailer…"] = catalog_value(catalog, "Ouvrir FileMailer…", locale)
        directory = RESOURCES / f"{locale}.lproj"
        directory.mkdir(parents=True, exist_ok=True)
        content = "\n".join(
            f'"{quote(key)}" = "{quote(value)}";'
            for key, value in values.items()
        )
        (directory / "Localizable.strings").write_text(
            content + "\n", encoding="utf-8"
        )


if __name__ == "__main__":
    main()
