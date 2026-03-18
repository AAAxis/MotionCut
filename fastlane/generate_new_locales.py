#!/usr/bin/env python3
"""Generate metadata for the 8 new ASC locales: hu, ro, cs, pl, el, hi, uk, he"""
import os

BASE = os.path.dirname(os.path.abspath(__file__)) + "/metadata"
PRIVACY_URL = "https://holylabs.net/privacy"
SUPPORT_URL = "https://holylabs.net/support"

NAMES = {
    "hu": "CreatorAI - AI Videó Készítő",
    "ro": "CreatorAI - Creator Video AI",
    "cs": "CreatorAI - AI Video Tvůrce",
    "pl": "CreatorAI - Kreator Wideo AI",
    "el": "CreatorAI - Δημιουργός AI",
    "hi": "CreatorAI - AI वीडियो मेकर",
    "uk": "CreatorAI - ШІ Відео Студія",
    "he": "CreatorAI - יוצר וידאו AI",
}

METADATA = {
    "hu": {
        "subtitle": "AI Videó, Avatár és Hirdetés",
        "keywords": "ai video keszito,szovegbol video,ai avatar,video hirdetes,ugc video,ai influencer,beat sync",
        "description": """Alakítsd bármely ötletedet virális videóvá másodpercek alatt — szerkesztési tudás nélkül.

A CreatorAI a vezető AI-alapú videókészítő alkalmazás tartalomkészítők, marketingesek és márkák számára. Hozz létre lenyűgöző videókat, UGC-stílusú hirdetéseket, AI-avatárokat és közösségi médiatartalmat egyszerű szöveggel.

AMIT LÉTREHOZHATSZ
• AI-videógenerátor — írj promptot, kapj professzionális videót
• AI-avatárok és influencerek — hiperrealisztikus digitális műsorvezetők
• UGC-videóhirdetések — hiteles felhasználói stílusú tartalom
• Beat Sync videók — klipek automatikus szinkronizálása zenére
• Hirdetéskészítő — TikTok, Reels és YouTube Shorts hirdetések

NÖVEKEDÉSRE TERVEZVE
• 4K minőség minden platformhoz optimalizálva
• Közvetlen export a TikTok-ra, Instagram Reels-re, YouTube Shorts-ra
• Képarány váltás egy érintéssel (9:16, 1:1, 16:9)
• AI hangalámondás 30+ nyelven

500 EZER+ ALKOTÓ BIZALMA

Kezdd ingyen. Nincs vízjel az első videón.

KREDIT INFO
A CreatorAI kredit rendszert használ. Egyszeri vásárlások. Nincs előfizetés.

Adatvédelem: https://holylabs.net/privacy""",
        "promotional_text": "Új: AI Avatár Stúdió — hozd létre digitális ikredet percek alatt. Korlátozott ideig 50% kedvezmény!",
        "release_notes": "• Új AI Avatár Stúdió — hiperrealisztikus digitális műsorvezetők\n• Videó renderelés 3× gyorsabb\n• Beat Sync fejlesztések automatikus tempóérzékeléssel\n• Hibajavítások és teljesítményjavítások",
    },
    "ro": {
        "subtitle": "Video AI, Avataruri si Reclame",
        "keywords": "generator video ai,text la video,avatar ai,reclama video,ugc video,influencer ai,beat sync",
        "description": """Transformă orice idee într-un video viral în câteva secunde — fără abilități de editare.

CreatorAI este aplicația de creare video cu AI pentru creatori de conținut, marketeri și branduri. Generează videoclipuri uimitoare, reclame în stil UGC, avataruri AI și conținut pentru rețele sociale dintr-un simplu text.

CE POȚI CREA
• Generator video AI — scrie un prompt, obține un video profesional
• Avataruri și influenceri AI — prezentatori digitali hiperrealisti
• Reclame video UGC — conținut autentic în stilul utilizatorilor
• Videoclipuri Beat Sync — sincronizare automată cu muzica
• Creator de reclame — ads pentru TikTok, Reels și YouTube Shorts

CONSTRUIT PENTRU CREȘTERE
• Calitate 4K optimizată pentru fiecare platformă
• Export direct pe TikTok, Instagram Reels, YouTube Shorts
• Schimbare format într-o atingere (9:16, 1:1, 16:9)
• Voce AI în 30+ limbi

ALES DE 500K+ CREATORI

Începe gratuit. Fără filigran pe primul video.

INFO CREDITE
CreatorAI folosește un sistem de credite. Achiziții unice. Nu necesită abonament.

Confidențialitate: https://holylabs.net/privacy""",
        "promotional_text": "Nou: AI Avatar Studio — creează-ți geamănul digital în minute. 50% reducere la pachetele de credite!",
        "release_notes": "• Nou AI Avatar Studio — prezentatori digitali hiperrealisti\n• Redare video de 3× mai rapidă\n• Îmbunătățiri Beat Sync cu detectare automată tempo\n• Remedieri erori și îmbunătățiri performanță",
    },
    "cs": {
        "subtitle": "AI Video, Avatary a Reklamy",
        "keywords": "generator ai videa,text na video,ai avatar,video reklama,ugc video,ai influencer,beat sync",
        "description": """Proměň jakýkoli nápad ve virální video během sekund — bez znalostí editace.

CreatorAI je přední aplikace pro tvorbu AI videí pro tvůrce obsahu, marketéry a značky. Vytváří úžasná videa, UGC-style reklamy, AI avatary a obsah pro sociální média z jednoduchého textu.

CO MŮŽEŠ VYTVOŘIT
• AI generátor videí — napiš prompt, získej profesionální video
• AI avatary a influenceři — hyperrealistickí digitální moderátoři
• UGC video reklamy — autentický obsah ve stylu uživatelů
• Beat Sync videa — automatická synchronizace klipů s hudbou
• Tvůrce reklam — ads pro TikTok, Reels a YouTube Shorts

NAVRŽENO PRO RŮST
• Kvalita 4K optimalizovaná pro každou platformu
• Přímý export na TikTok, Instagram Reels, YouTube Shorts
• Přepnutí poměru stran jedním dotekem (9:16, 1:1, 16:9)
• AI hlas v 30+ jazycích

DŮVĚŘUJE 500K+ TVŮRCŮ

Začni zdarma. Bez vodoznaku na prvním videu.

INFO O KREDITECH
CreatorAI používá kreditový systém. Jednorázové nákupy. Bez předplatného.

Ochrana soukromí: https://holylabs.net/privacy""",
        "promotional_text": "Nové: AI Avatar Studio — vytvoř svého digitálního dvojníka za minuty. 50% sleva na balíčky kreditů!",
        "release_notes": "• Nové AI Avatar Studio — hyperrealistickí digitální moderátoři\n• Renderování videa až 3× rychlejší\n• Vylepšení Beat Sync s automatickým rozpoznáváním tempa\n• Opravy chyb a vylepšení výkonu",
    },
    "pl": {
        "subtitle": "AI Wideo, Awatary i Reklamy",
        "keywords": "generator wideo ai,tekst na wideo,awatar ai,reklama wideo,ugc wideo,influencer ai,beat sync",
        "description": """Zamień każdy pomysł w wirusowy film w kilka sekund — bez umiejętności edycji.

CreatorAI to wiodąca aplikacja do tworzenia wideo AI dla twórców treści, marketerów i marek. Twórz niesamowite filmy, reklamy w stylu UGC, awatary AI i treści do mediów społecznościowych z prostego tekstu.

CO MOŻESZ TWORZYĆ
• Generator wideo AI — wpisz prompt, otrzymaj profesjonalny film
• Awatary i influencerzy AI — hiperrealistyczni cyfrowi prezenterzy
• Reklamy wideo UGC — autentyczne treści w stylu użytkowników
• Filmy Beat Sync — automatyczna synchronizacja klipów z muzyką
• Kreator reklam — ads dla TikTok, Reels i YouTube Shorts

ZBUDOWANE DLA WZROSTU
• Jakość 4K zoptymalizowana pod każdą platformę
• Bezpośredni eksport do TikTok, Instagram Reels, YouTube Shorts
• Zmiana proporcji jednym dotknięciem (9:16, 1:1, 16:9)
• Lektorat AI w 30+ językach

ZAUFAŁO 500 TYS.+ TWÓRCÓW

Zacznij bezpłatnie. Bez znaku wodnego na pierwszym filmie.

INFORMACJE O KREDYTACH
CreatorAI używa systemu kredytów. Jednorazowe zakupy. Bez subskrypcji.

Prywatność: https://holylabs.net/privacy""",
        "promotional_text": "Nowe: AI Avatar Studio — stwórz cyfrowego sobowtóra w minuty. 50% zniżki na pakiety kredytów!",
        "release_notes": "• Nowe AI Avatar Studio — hiperrealistyczni cyfrowi prezenterzy\n• Renderowanie wideo do 3× szybciej\n• Ulepszenia Beat Sync z automatycznym wykrywaniem tempa\n• Poprawki błędów i ulepszenia wydajności",
    },
    "el": {
        "subtitle": "AI Βίντεο, Άβαταρ, Διαφημίσεις",
        "keywords": "δημιουργος βιντεο ai,κειμενο σε βιντεο,avatar ai,διαφημιση βιντεο,ugc βιντεο,influencer ai",
        "description": """Μετατρέψτε κάθε ιδέα σε viral βίντεο σε δευτερόλεπτα — χωρίς δεξιότητες επεξεργασίας.

Το CreatorAI είναι η κορυφαία εφαρμογή δημιουργίας βίντεο AI για δημιουργούς περιεχομένου, marketers και brands. Δημιουργήστε εκπληκτικά βίντεο, διαφημίσεις τύπου UGC, AI avatar και περιεχόμενο μέσων κοινωνικής δικτύωσης από απλό κείμενο.

ΤΙ ΜΠΟΡΕΙΤΕ ΝΑ ΔΗΜΙΟΥΡΓΗΣΕΤΕ
• Γεννήτρια βίντεο AI — γράψτε prompt, λάβετε επαγγελματικό βίντεο
• AI Avatar και influencer — υπεραληθινοί ψηφιακοί παρουσιαστές
• Διαφημίσεις βίντεο UGC — αυθεντικό περιεχόμενο τύπου χρήστη
• Βίντεο Beat Sync — αυτόματος συγχρονισμός κλιπ με μουσική
• Δημιουργός διαφημίσεων — ads για TikTok, Reels και YouTube Shorts

ΣΧΕΔΙΑΣΜΕΝΟ ΓΙΑ ΑΝΑΠΤΥΞΗ
• Ποιότητα 4K βελτιστοποιημένη για κάθε πλατφόρμα
• Άμεση εξαγωγή στο TikTok, Instagram Reels, YouTube Shorts
• Αλλαγή αναλογίας με ένα άγγιγμα (9:16, 1:1, 16:9)
• AI φωνή σε 30+ γλώσσες

ΕΜΠΙΣΤΕΥΟΝΤΑΙ 500 ΧΙΛΙΑΔΕΣ+ ΔΗΜΙΟΥΡΓΟΙ

Ξεκινήστε δωρεάν. Χωρίς υδατογράφημα στο πρώτο βίντεο.

ΠΛΗΡΟΦΟΡΙΕΣ ΠΙΣΤΩΣΕΩΝ
Το CreatorAI χρησιμοποιεί σύστημα πιστώσεων. Εφάπαξ αγορές. Χωρίς συνδρομή.

Απόρρητο: https://holylabs.net/privacy""",
        "promotional_text": "Νέο: AI Avatar Studio — δημιουργήστε τον ψηφιακό σας δίδυμο σε λεπτά. 50% έκπτωση σε πακέτα πιστώσεων!",
        "release_notes": "• Νέο AI Avatar Studio — υπεραληθινοί ψηφιακοί παρουσιαστές\n• Απόδοση βίντεο έως 3× πιο γρήγορη\n• Βελτιώσεις Beat Sync με αυτόματη ανίχνευση tempo\n• Διορθώσεις σφαλμάτων και βελτιώσεις απόδοσης",
    },
    "hi": {
        "subtitle": "AI वीडियो, अवतार और विज्ञापन",
        "keywords": "ai वीडियो जनरेटर,टेक्स्ट टू वीडियो,ai अवतार,वीडियो विज्ञापन,ugc वीडियो,ai इन्फ्लुएंसर",
        "description": """किसी भी विचार को सेकंड में वायरल वीडियो में बदलें — बिना किसी एडिटिंग स्किल के।

CreatorAI कंटेंट क्रिएटर्स, मार्केटर्स और ब्रांड्स के लिए #1 AI वीडियो क्रिएशन ऐप है। एक साधारण टेक्स्ट से शानदार वीडियो, UGC-स्टाइल विज्ञापन, AI अवतार और सोशल मीडिया कंटेंट बनाएं।

आप क्या बना सकते हैं
• AI वीडियो जनरेटर — प्रॉम्प्ट टाइप करें, प्रोफेशनल वीडियो पाएं
• AI अवतार और इन्फ्लुएंसर — हाइपर-रियलिस्टिक डिजिटल प्रेजेंटर
• UGC वीडियो विज्ञापन — असली यूजर-स्टाइल कंटेंट
• Beat Sync वीडियो — क्लिप्स को म्यूजिक के साथ ऑटो-सिंक
• ऐड मेकर — TikTok, Reels और YouTube Shorts के लिए

ग्रोथ के लिए बनाया गया
• हर प्लेटफॉर्म के लिए 4K क्वालिटी
• TikTok, Instagram Reels, YouTube Shorts पर सीधे एक्सपोर्ट
• एक टैप में आस्पेक्ट रेशियो बदलें (9:16, 1:1, 16:9)
• 30+ भाषाओं में AI वॉयसओवर

500K+ क्रिएटर्स का भरोसा

फ्री में शुरू करें। पहले वीडियो पर कोई वॉटरमार्क नहीं।

क्रेडिट जानकारी
CreatorAI क्रेडिट सिस्टम उपयोग करता है। एकमुश्त खरीद। कोई सब्सक्रिप्शन नहीं।

गोपनीयता: https://holylabs.net/privacy""",
        "promotional_text": "नया: AI अवतार स्टूडियो — मिनटों में अपना डिजिटल ट्विन बनाएं। क्रेडिट पैक पर 50% की छूट!",
        "release_notes": "• नया AI अवतार स्टूडियो — हाइपर-रियलिस्टिक डिजिटल प्रेजेंटर\n• वीडियो रेंडरिंग 3× तक तेज\n• ऑटो टेम्पो डिटेक्शन के साथ Beat Sync सुधार\n• बग फिक्स और परफॉर्मेंस सुधार",
    },
    "uk": {
        "subtitle": "ШІ відео, аватари та реклама",
        "keywords": "генератор відео шї,текст у відео,аватар шї,відеореклама,ugc відео,шї інфлюенсер,біт синк",
        "description": """Перетворюй будь-яку ідею на вірусне відео за секунди — без навичок монтажу.

CreatorAI — провідний застосунок для створення відео зі ШІ для контент-мейкерів, маркетологів і брендів. Генеруй вражаючі відео, рекламу в стилі UGC, ШІ-аватари та контент для соцмереж із простого тексту.

ЩО ТИ МОЖЕШ СТВОРИТИ
• Генератор відео ШІ — введи промпт, отримай професійне відео
• ШІ-аватари та інфлюенсери — гіперреалістичні цифрові ведучі
• UGC-відеореклама — автентичний стиль користувачів
• Відео з бітом — автосинхронізація з музикою
• Конструктор реклами — ads для TikTok, Reels і YouTube Shorts

СТВОРЕНО ДЛЯ ЗРОСТАННЯ
• Якість 4K для кожної платформи
• Прямий експорт у TikTok, Instagram Reels, YouTube Shorts
• Зміна співвідношення сторін одним дотиком (9:16, 1:1, 16:9)
• ШІ-озвучення 30+ мовами

ДОВІРЯЮТЬ 500К+ АВТОРІВ

Почни безкоштовно. Без водяного знаку на першому відео.

ПРО КРЕДИТИ
CreatorAI використовує кредитну систему. Разові покупки. Підписка не потрібна.

Конфіденційність: https://holylabs.net/privacy""",
        "promotional_text": "Нове: Студія ШІ-аватарів — створи цифрового двійника за хвилини. Знижка 50% на пакети кредитів!",
        "release_notes": "• Нова Студія ШІ-аватарів — гіперреалістичні цифрові ведучі\n• Прискорення рендерингу відео до 3×\n• Покращення біт-синку з автодетекцією темпу\n• Виправлення помилок і підвищення продуктивності",
    },
    "he": {
        "subtitle": "וידאו AI, אווטרים ופרסומות",
        "keywords": "יוצר וידאו ai,טקסט לוידאו,אווטר ai,פרסומת וידאו,ugc וידאו,אינפלואנסר ai,beat sync",
        "description": """הפוך כל רעיון לוידאו ויראלי תוך שניות — ללא כישורי עריכה.

CreatorAI הוא אפליקציית יצירת הוידאו המובילה בעזרת AI עבור יוצרי תוכן, משווקים ומותגים. צור סרטונים מדהימים, מודעות בסגנון UGC, אווטרים של AI ותוכן לרשתות חברתיות מטקסט פשוט.

מה תוכל ליצור
• גנרטור וידאו AI — הקלד הנחיה, קבל וידאו מקצועי
• אווטרים ואינפלואנסרים של AI — מגישים דיגיטליים היפר-ריאליסטיים
• מודעות וידאו UGC — תוכן אותנטי בסגנון משתמשים
• וידאו Beat Sync — סנכרון אוטומטי של קליפים עם מוזיקה
• יוצר מודעות — מודעות לTikTok, Reels ו-YouTube Shorts

בנוי לצמיחה
• איכות 4K מותאמת לכל פלטפורמה
• ייצוא ישיר לTikTok, Instagram Reels, YouTube Shorts
• שינוי יחס תמונה בהקשה אחת (9:16, 1:1, 16:9)
• קריינות AI ב-30+ שפות

500K+ יוצרים סומכים עלינו

התחל בחינם. ללא סימן מים בוידאו הראשון.

מידע על קרדיטים
CreatorAI משתמש במערכת קרדיטים. רכישות חד-פעמיות. ללא מנוי.

פרטיות: https://holylabs.net/privacy""",
        "promotional_text": "חדש: AI Avatar Studio — צור את התאום הדיגיטלי שלך בדקות. 50% הנחה על חבילות קרדיטים!",
        "release_notes": "• AI Avatar Studio חדש — מגישים דיגיטליים היפר-ריאליסטיים\n• עיבוד וידאו עד 3× מהיר יותר\n• שיפורים ב-Beat Sync עם זיהוי טמפו אוטומטי\n• תיקוני באגים ושיפורי ביצועים",
    },
}

def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

for lang, data in METADATA.items():
    folder = f"{BASE}/{lang}"
    write_file(f"{folder}/subtitle.txt", data["subtitle"])
    write_file(f"{folder}/keywords.txt", data["keywords"])
    write_file(f"{folder}/description.txt", data["description"])
    write_file(f"{folder}/promotional_text.txt", data["promotional_text"])
    write_file(f"{folder}/release_notes.txt", data["release_notes"])
    write_file(f"{folder}/privacy_url.txt", PRIVACY_URL)
    write_file(f"{folder}/support_url.txt", SUPPORT_URL)
    write_file(f"{folder}/name.txt", NAMES[lang])
    print(f"✓ {lang}: subtitle={len(data['subtitle'])} chars")

print(f"\nDone! {len(METADATA)} locales written.")
