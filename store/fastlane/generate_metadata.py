#!/usr/bin/env python3
"""Generate optimized ASO metadata for all 20 languages into fastlane/metadata/"""

import os

BASE = os.path.dirname(os.path.abspath(__file__)) + "/metadata"
PRIVACY_URL = "https://holylabs.net/privacy"
SUPPORT_URL = "https://holylabs.net/support"

# Each language: subtitle, keywords (max 100 chars), description, promotional_text, release_notes
METADATA = {
    "en-US": {
        "subtitle": "AI Video, Avatars & Ads Maker",
        "keywords": "ai video generator,text to video,ai avatar,video ad maker,ugc video,ai influencer,beat sync",
        "description": """Turn any idea into a viral video in seconds — no editing skills needed.

CreatorAI is the #1 AI-powered video creation app for content creators, marketers, and brands. Generate stunning videos, UGC-style ads, AI avatars, and social media content from a simple text prompt.

🎬 WHAT YOU CAN CREATE
• AI Video Generator — type a prompt, get a polished video
• AI Avatars & Influencers — create hyper-realistic digital presenters
• UGC Video Ads — generate authentic user-generated-style ad content
• Beat Sync Videos — auto-sync clips to any music track
• Ad Maker — produce scroll-stopping ads for TikTok, Reels & YouTube Shorts

🚀 BUILT FOR GROWTH
• 4K-quality renders optimized for every platform
• Export directly to TikTok, Instagram Reels, YouTube Shorts, and more
• One-tap aspect ratio switch (9:16, 1:1, 16:9)
• AI voiceover in 30+ languages

🏆 TRUSTED BY 500K+ CREATORS
Whether you're a solo creator, agency, or brand — CreatorAI gives you a professional studio in your pocket.

Start free. No watermark on first video.

SUBSCRIPTION INFO
CreatorAI uses a credit-based system. Credits are purchased as consumable in-app purchases. No subscription required.

Privacy Policy: https://holylabs.net/privacy
Terms of Use: https://holylabs.net/terms""",
        "promotional_text": "New: AI Avatar Studio — create your digital twin in minutes. Limited-time 50% off credit packs!",
        "release_notes": "• New AI Avatar Studio — build a hyper-realistic digital presenter\n• Faster video rendering (up to 3×)\n• Beat Sync improvements with auto tempo detection\n• Bug fixes and performance improvements",
    },
    "en-GB": {
        "subtitle": "AI Video, Avatars & Ads Maker",
        "keywords": "ai video generator,text to video,ai avatar,video ad maker,ugc video,ai influencer,beat sync",
        "description": """Turn any idea into a viral video in seconds — no editing skills needed.

CreatorAI is the leading AI-powered video creation app for content creators, marketers, and brands. Generate stunning videos, UGC-style ads, AI avatars, and social media content from a simple text prompt.

🎬 WHAT YOU CAN CREATE
• AI Video Generator — type a prompt, get a polished video
• AI Avatars & Influencers — create hyper-realistic digital presenters
• UGC Video Ads — generate authentic user-generated-style ad content
• Beat Sync Videos — auto-sync clips to any music track
• Ad Maker — produce scroll-stopping ads for TikTok, Reels & YouTube Shorts

🚀 BUILT FOR GROWTH
• 4K-quality renders optimised for every platform
• Export directly to TikTok, Instagram Reels, YouTube Shorts and more
• One-tap aspect ratio switch (9:16, 1:1, 16:9)
• AI voiceover in 30+ languages

🏆 TRUSTED BY 500K+ CREATORS
Whether you're a solo creator, agency, or brand — CreatorAI gives you a professional studio in your pocket.

Start free. No watermark on your first video.

CREDIT INFO
CreatorAI uses a credit-based system. Credits are purchased as one-off in-app purchases. No subscription required.

Privacy Policy: https://holylabs.net/privacy
Terms of Use: https://holylabs.net/terms""",
        "promotional_text": "New: AI Avatar Studio — create your digital twin in minutes. Limited-time 50% off credit packs!",
        "release_notes": "• New AI Avatar Studio — build a hyper-realistic digital presenter\n• Faster video rendering (up to 3×)\n• Beat Sync improvements with auto tempo detection\n• Bug fixes and performance improvements",
    },
    "en-CA": {
        "subtitle": "AI Video, Avatars & Ads Maker",
        "keywords": "ai video generator,text to video,ai avatar,video ad maker,ugc video,ai influencer,beat sync",
        "description": """Turn any idea into a viral video in seconds — no editing skills needed.

CreatorAI is the #1 AI-powered video creation app for content creators, marketers, and brands. Generate stunning videos, UGC-style ads, AI avatars, and social media content from a simple text prompt.

🎬 WHAT YOU CAN CREATE
• AI Video Generator — type a prompt, get a polished video
• AI Avatars & Influencers — create hyper-realistic digital presenters
• UGC Video Ads — generate authentic user-generated-style ad content
• Beat Sync Videos — auto-sync clips to any music track
• Ad Maker — produce scroll-stopping ads for TikTok, Reels & YouTube Shorts

🚀 BUILT FOR GROWTH
• 4K-quality renders optimized for every platform
• Export directly to TikTok, Instagram Reels, YouTube Shorts, and more
• One-tap aspect ratio switch (9:16, 1:1, 16:9)
• AI voiceover in 30+ languages

🏆 TRUSTED BY 500K+ CREATORS
Whether you're a solo creator, agency, or brand — CreatorAI gives you a professional studio in your pocket.

Start free. No watermark on first video.

CREDIT INFO
CreatorAI uses a credit-based system. Credits are purchased as consumable in-app purchases. No subscription required.

Privacy Policy: https://holylabs.net/privacy
Terms of Use: https://holylabs.net/terms""",
        "promotional_text": "New: AI Avatar Studio — create your digital twin in minutes. Limited-time 50% off credit packs!",
        "release_notes": "• New AI Avatar Studio — build a hyper-realistic digital presenter\n• Faster video rendering (up to 3×)\n• Beat Sync improvements with auto tempo detection\n• Bug fixes and performance improvements",
    },
    "de-DE": {
        "subtitle": "KI-Video, Avatare & Werbung",
        "keywords": "ki video erstellen,text zu video,ki avatar,video werbung,ugc video,ki influencer,beat sync",
        "description": """Verwandle jede Idee in Sekunden in ein virales Video – ganz ohne Schnittkenntnisse.

CreatorAI ist die führende KI-Video-App für Content Creator, Marketer und Marken. Erstelle beeindruckende Videos, UGC-Style-Werbeanzeigen, KI-Avatare und Social-Media-Content – einfach per Texteingabe.

🎬 WAS DU ERSTELLEN KANNST
• KI-Videogenerator — Prompt eingeben, fertiges Video erhalten
• KI-Avatare & Influencer — hyperrealistische digitale Präsentatoren
• UGC-Videoanzeigen — authentischer User-Generated-Content-Stil
• Beat-Sync-Videos — Clips automatisch zur Musik synchronisieren
• Anzeigen-Maker — auffällige Ads für TikTok, Reels & YouTube Shorts

🚀 FÜR WACHSTUM GEMACHT
• 4K-Qualität für alle Plattformen optimiert
• Direktexport zu TikTok, Instagram Reels, YouTube Shorts
• Ein-Tipp-Seitenverhältniswechsel (9:16, 1:1, 16:9)
• KI-Sprachausgabe in 30+ Sprachen

🏆 VON 500K+ CREATORS VERTRAUT
Egal ob Solo-Creator, Agentur oder Marke — CreatorAI ist dein professionelles Studio in der Tasche.

Kostenlos starten. Kein Wasserzeichen auf dem ersten Video.

ABO-INFO
CreatorAI nutzt ein Credits-System. Credits werden als einmalige In-App-Käufe erworben. Kein Abonnement erforderlich.

Datenschutz: https://holylabs.net/privacy
Nutzungsbedingungen: https://holylabs.net/terms""",
        "promotional_text": "Neu: KI-Avatar-Studio — erstelle deinen digitalen Zwilling in Minuten. Jetzt 50 % Rabatt auf Credits!",
        "release_notes": "• Neues KI-Avatar-Studio — hyperrealistische digitale Präsentatoren\n• Bis zu 3× schnelleres Video-Rendering\n• Beat-Sync mit automatischer Tempoanpassung\n• Fehlerbehebungen und Leistungsverbesserungen",
    },
    "fr-FR": {
        "subtitle": "Vidéo IA, Avatars & Publicités",
        "keywords": "generateur video ia,texte en video,avatar ia,publicite video,ugc video,influenceur ia,beat sync",
        "description": """Transforme n'importe quelle idée en vidéo virale en quelques secondes — sans compétences en montage.

CreatorAI est l'application de création vidéo IA n°1 pour les créateurs de contenu, marketeurs et marques. Génère des vidéos époustouflantes, des publicités style UGC, des avatars IA et du contenu réseaux sociaux à partir d'un simple texte.

🎬 CE QUE TU PEUX CRÉER
• Générateur vidéo IA — saisis un prompt, obtiens une vidéo professionnelle
• Avatars & influenceurs IA — présentateurs numériques hyperréalistes
• Publicités vidéo UGC — contenu authentique style utilisateur
• Vidéos Beat Sync — synchronise automatiquement les clips sur la musique
• Créateur de publicités — ads percutantes pour TikTok, Reels & YouTube Shorts

🚀 CONÇU POUR LA CROISSANCE
• Rendus 4K optimisés pour chaque plateforme
• Export direct vers TikTok, Instagram Reels, YouTube Shorts
• Changement de ratio en un tap (9:16, 1:1, 16:9)
• Voix off IA en 30+ langues

🏆 FAIT CONFIANCE PAR 500K+ CRÉATEURS

Commence gratuitement. Pas de filigrane sur la première vidéo.

INFO CRÉDITS
CreatorAI utilise un système de crédits. Les crédits sont achetés en achats in-app uniques. Pas d'abonnement requis.

Confidentialité : https://holylabs.net/privacy""",
        "promotional_text": "Nouveau : Studio Avatar IA — crée ton jumeau numérique en minutes. -50% sur les packs de crédits !",
        "release_notes": "• Nouveau Studio Avatar IA — présentateurs numériques hyperréalistes\n• Rendu vidéo jusqu'à 3× plus rapide\n• Améliorations Beat Sync avec détection automatique du tempo\n• Corrections de bugs et améliorations des performances",
    },
    "es-ES": {
        "subtitle": "Video IA, Avatares y Anuncios",
        "keywords": "generador video ia,texto a video,avatar ia,anuncios video,ugc video,influencer ia,beat sync",
        "description": """Convierte cualquier idea en un vídeo viral en segundos — sin necesidad de edición.

CreatorAI es la app de creación de vídeo con IA líder para creadores de contenido, marketers y marcas. Genera vídeos impresionantes, anuncios estilo UGC, avatares IA y contenido para redes sociales con un simple texto.

🎬 QUÉ PUEDES CREAR
• Generador de vídeo IA — escribe un prompt, obtén un vídeo profesional
• Avatares e influencers IA — presentadores digitales hiperrealistas
• Anuncios de vídeo UGC — contenido auténtico estilo usuario
• Vídeos Beat Sync — sincroniza clips con música automáticamente
• Creador de anuncios — ads para TikTok, Reels y YouTube Shorts

🚀 DISEÑADO PARA EL CRECIMIENTO
• Renderizados en 4K para cada plataforma
• Exporta directamente a TikTok, Instagram Reels, YouTube Shorts
• Cambio de relación de aspecto en un toque (9:16, 1:1, 16:9)
• Voz en off IA en más de 30 idiomas

🏆 MÁS DE 500K CREADORES NOS CONFÍAN

Empieza gratis. Sin marca de agua en el primer vídeo.

INFO DE CRÉDITOS
CreatorAI usa un sistema de créditos. No requiere suscripción.

Privacidad: https://holylabs.net/privacy""",
        "promotional_text": "Nuevo: Estudio de Avatares IA — crea tu gemelo digital en minutos. ¡50% de descuento en créditos!",
        "release_notes": "• Nuevo Estudio de Avatares IA — presentadores digitales hiperrealistas\n• Renderizado hasta 3× más rápido\n• Mejoras en Beat Sync con detección automática de tempo\n• Correcciones de errores y mejoras de rendimiento",
    },
    "es-MX": {
        "subtitle": "Video IA, Avatares y Anuncios",
        "keywords": "generador video ia,texto a video,avatar ia,anuncios video,ugc video,influencer ia,beat sync",
        "description": """Convierte cualquier idea en un video viral en segundos — sin necesitar edición.

CreatorAI es la app de creación de video con IA líder para creadores de contenido, marketers y marcas. Genera videos increíbles, anuncios estilo UGC, avatares IA y contenido para redes sociales con un simple texto.

🎬 QUÉ PUEDES CREAR
• Generador de video IA — escribe un prompt, obtén un video profesional
• Avatares e influencers IA — presentadores digitales hiperrealistas
• Anuncios de video UGC — contenido auténtico estilo usuario
• Videos Beat Sync — sincroniza clips con música automáticamente
• Creador de anuncios — ads para TikTok, Reels y YouTube Shorts

🚀 DISEÑADO PARA EL CRECIMIENTO
• Renders en 4K para cada plataforma
• Exporta directamente a TikTok, Instagram Reels, YouTube Shorts
• Cambio de relación de aspecto en un toque (9:16, 1:1, 16:9)
• Voz en off IA en más de 30 idiomas

🏆 MÁS DE 500K CREADORES NOS ELIGEN

Comienza gratis. Sin marca de agua en el primer video.

INFO DE CRÉDITOS
CreatorAI usa un sistema de créditos. No requiere suscripción.

Privacidad: https://holylabs.net/privacy""",
        "promotional_text": "Nuevo: Estudio de Avatares IA — crea tu gemelo digital en minutos. ¡50% de descuento en créditos!",
        "release_notes": "• Nuevo Estudio de Avatares IA — presentadores digitales hiperrealistas\n• Renderizado hasta 3× más rápido\n• Mejoras en Beat Sync con detección automática de tempo\n• Correcciones de errores y mejoras de rendimiento",
    },
    "pt-BR": {
        "subtitle": "Vídeo IA, Avatares e Anúncios",
        "keywords": "gerador video ia,texto para video,avatar ia,anuncio video,ugc video,influencer ia,beat sync",
        "description": """Transforme qualquer ideia em um vídeo viral em segundos — sem precisar editar.

CreatorAI é o app líder de criação de vídeo com IA para criadores de conteúdo, profissionais de marketing e marcas. Gere vídeos incríveis, anúncios estilo UGC, avatares de IA e conteúdo para redes sociais com um simples texto.

🎬 O QUE VOCÊ PODE CRIAR
• Gerador de vídeo IA — escreva um prompt, receba um vídeo profissional
• Avatares e influenciadores IA — apresentadores digitais hiperrealistas
• Anúncios de vídeo UGC — conteúdo autêntico estilo usuário
• Vídeos Beat Sync — sincronize clipes com música automaticamente
• Criador de anúncios — ads para TikTok, Reels e YouTube Shorts

🚀 FEITO PARA O CRESCIMENTO
• Renderização em 4K otimizada para cada plataforma
• Exporte diretamente para TikTok, Instagram Reels, YouTube Shorts
• Troca de proporção em um toque (9:16, 1:1, 16:9)
• Narração IA em mais de 30 idiomas

🏆 MAIS DE 500MIL CRIADORES CONFIAM

Comece de graça. Sem marca d'água no primeiro vídeo.

INFO DE CRÉDITOS
CreatorAI usa sistema de créditos. Sem assinatura necessária.

Privacidade: https://holylabs.net/privacy""",
        "promotional_text": "Novo: Estúdio de Avatares IA — crie seu gêmeo digital em minutos. 50% de desconto nos pacotes de créditos!",
        "release_notes": "• Novo Estúdio de Avatares IA — apresentadores digitais hiperrealistas\n• Renderização de vídeo até 3× mais rápida\n• Melhorias no Beat Sync com detecção automática de tempo\n• Correções de bugs e melhorias de desempenho",
    },
    "pt-PT": {
        "subtitle": "Vídeo IA, Avatares e Anúncios",
        "keywords": "gerador video ia,texto para video,avatar ia,anuncio video,ugc video,influencer ia,beat sync",
        "description": """Transforma qualquer ideia num vídeo viral em segundos — sem precisares de editar.

CreatorAI é a app líder de criação de vídeo com IA para criadores de conteúdo, profissionais de marketing e marcas. Gera vídeos incríveis, anúncios estilo UGC, avatares de IA e conteúdo para redes sociais com um simples texto.

🎬 O QUE PODES CRIAR
• Gerador de vídeo IA — escreve um prompt, recebe um vídeo profissional
• Avatares e influenciadores IA — apresentadores digitais hiperrealistas
• Anúncios de vídeo UGC — conteúdo autêntico estilo utilizador
• Vídeos Beat Sync — sincroniza clips com música automaticamente
• Criador de anúncios — ads para TikTok, Reels e YouTube Shorts

🚀 CRIADO PARA O CRESCIMENTO
• Renderização em 4K otimizada para cada plataforma
• Exporta diretamente para TikTok, Instagram Reels, YouTube Shorts
• Mudança de proporção num toque (9:16, 1:1, 16:9)
• Narração IA em mais de 30 idiomas

🏆 MAIS DE 500MIL CRIADORES CONFIAM

Começa de graça. Sem marca de água no primeiro vídeo.

INFO DE CRÉDITOS
CreatorAI usa sistema de créditos. Sem subscrição necessária.

Privacidade: https://holylabs.net/privacy""",
        "promotional_text": "Novo: Estúdio de Avatares IA — cria o teu gémeo digital em minutos. 50% de desconto nos pacotes de créditos!",
        "release_notes": "• Novo Estúdio de Avatares IA — apresentadores digitais hiperrealistas\n• Renderização de vídeo até 3× mais rápida\n• Melhorias no Beat Sync com deteção automática de tempo\n• Correções de erros e melhorias de desempenho",
    },
    "ar-SA": {
        "subtitle": "فيديو ذكاء اصطناعي وإعلانات",
        "keywords": "فيديو ذكاء اصطناعي,نص إلى فيديو,أفاتار ذكاء,إعلان فيديو,مؤثر ذكاء اصطناعي,مزامنة موسيقى",
        "description": """حوّل أي فكرة إلى فيديو رائج في ثوانٍ — دون الحاجة لمهارات مونتاج.

CreatorAI هو تطبيق إنشاء الفيديو بالذكاء الاصطناعي الرائد للمبدعين والمسوّقين والعلامات التجارية. أنشئ مقاطع مذهلة وإعلانات بأسلوب UGC وأفاتارات ذكاء اصطناعي ومحتوى وسائل التواصل الاجتماعي بمجرد نص بسيط.

🎬 ما يمكنك إنشاؤه
• منشئ فيديو ذكاء اصطناعي — اكتب وصفاً واحصل على فيديو احترافي
• أفاتارات ومؤثرون ذكاء اصطناعي — مقدمون رقميون فائقو الواقعية
• إعلانات فيديو UGC — محتوى أصيل بأسلوب المستخدمين
• فيديوهات مزامنة الموسيقى — تزامن تلقائي مع أي مقطع موسيقي
• صانع الإعلانات — إعلانات لافتة لـ TikTok وReels وYouTube Shorts

🚀 مصمم للنمو
• عرض بجودة 4K مُحسَّن لكل منصة
• تصدير مباشر إلى TikTok وInstagram Reels وYouTube Shorts
• تبديل نسبة الأبعاد بنقرة واحدة (9:16 و1:1 و16:9)
• تعليق صوتي بالذكاء الاصطناعي بأكثر من 30 لغة

🏆 يثق به أكثر من 500,000 منشئ محتوى

ابدأ مجاناً. لا علامة مائية على الفيديو الأول.

معلومات الرصيد
يستخدم CreatorAI نظام رصيد. تُشترى الأرصدة كعمليات شراء داخل التطبيق. لا اشتراك مطلوب.

الخصوصية: https://holylabs.net/privacy""",
        "promotional_text": "جديد: استوديو أفاتار الذكاء الاصطناعي — أنشئ توأمك الرقمي في دقائق. خصم 50% على حزم الرصيد لفترة محدودة!",
        "release_notes": "• استوديو أفاتار ذكاء اصطناعي جديد — مقدمون رقميون فائقو الواقعية\n• تسريع عرض الفيديو حتى 3 أضعاف\n• تحسينات مزامنة الموسيقى مع كشف الإيقاع التلقائي\n• إصلاحات وتحسينات في الأداء",
    },
    "ja": {
        "subtitle": "AI動画・アバター・広告メーカー",
        "keywords": "ai動画生成,テキストから動画,aiアバター,動画広告,ugc動画,aiインフルエンサー,ビート同期",
        "description": """どんなアイデアも数秒でバズる動画に — 編集スキル不要。

CreatorAIは、コンテンツクリエイター・マーケター・ブランド向けNo.1 AI動画作成アプリです。テキストを入力するだけで、プロ品質の動画、UGCスタイル広告、AIアバター、SNSコンテンツを生成できます。

🎬 作れるコンテンツ
• AI動画ジェネレーター — プロンプト入力で完成動画
• AIアバター＆インフルエンサー — 超リアルなデジタルプレゼンター
• UGC動画広告 — リアルなユーザー生成スタイルの広告
• ビート同期動画 — 音楽に自動同期
• 広告メーカー — TikTok・Reels・YouTube Shorts向け

🚀 成長のための設計
• 各プラットフォーム最適化の4K品質
• TikTok・Instagram Reels・YouTube Shortsに直接エクスポート
• ワンタップでアスペクト比切替（9:16・1:1・16:9）
• 30以上の言語でAI音声ナレーション

🏆 50万人以上のクリエイターに信頼

無料スタート。最初の動画はウォーターマークなし。

クレジット情報
CreatorAIはクレジット制。クレジットはアプリ内購入。サブスクリプション不要。

プライバシー: https://holylabs.net/privacy""",
        "promotional_text": "新機能: AIアバタースタジオ — 数分でデジタルツインを作成。期間限定クレジット50%オフ！",
        "release_notes": "• 新AIアバタースタジオ — 超リアルなデジタルプレゼンター\n• 動画レンダリングが最大3倍高速化\n• ビートシンク改善（自動テンポ検出）\n• バグ修正とパフォーマンス改善",
    },
    "ko": {
        "subtitle": "AI 비디오·아바타·광고 메이커",
        "keywords": "ai동영상생성,텍스트투비디오,ai아바타,동영상광고,ugc영상,ai인플루언서,비트싱크",
        "description": """어떤 아이디어든 몇 초 만에 바이럴 영상으로 — 편집 실력 필요 없음.

CreatorAI는 크리에이터, 마케터, 브랜드를 위한 No.1 AI 영상 제작 앱입니다. 텍스트만 입력하면 멋진 영상, UGC 스타일 광고, AI 아바타, SNS 콘텐츠를 생성합니다.

🎬 만들 수 있는 콘텐츠
• AI 영상 생성기 — 프롬프트 입력으로 완성 영상
• AI 아바타 & 인플루언서 — 초실사 디지털 진행자
• UGC 영상 광고 — 진짜 같은 사용자 스타일 광고
• 비트 싱크 영상 — 음악에 자동 동기화
• 광고 메이커 — TikTok·Reels·YouTube Shorts 광고

🚀 성장을 위한 설계
• 모든 플랫폼 최적화 4K 품질
• TikTok·Instagram Reels·YouTube Shorts 직접 내보내기
• 화면 비율 원터치 전환 (9:16·1:1·16:9)
• 30개 이상 언어 AI 나레이션

🏆 50만 크리에이터의 선택

무료로 시작. 첫 번째 영상 워터마크 없음.

크레딧 정보
CreatorAI는 크레딧 방식. 앱 내 구매로 충전. 구독 불필요.

개인정보: https://holylabs.net/privacy""",
        "promotional_text": "신규: AI 아바타 스튜디오 — 몇 분 만에 디지털 트윈 생성. 한정 크레딧 50% 할인!",
        "release_notes": "• 새 AI 아바타 스튜디오 — 초실사 디지털 진행자\n• 영상 렌더링 최대 3배 빠르게\n• 비트 싱크 개선 (자동 템포 감지)\n• 버그 수정 및 성능 개선",
    },
    "zh-Hans": {
        "subtitle": "AI视频、虚拟形象和广告",
        "keywords": "ai视频生成,文字转视频,ai虚拟形象,视频广告,ugc视频,ai网红,节拍同步",
        "description": """将任何想法在几秒内变成爆款视频 — 无需剪辑技能。

CreatorAI 是面向内容创作者、营销人员和品牌的领先 AI 视频创作应用。只需输入文字，即可生成精彩视频、UGC 风格广告、AI 虚拟形象和社交媒体内容。

🎬 你可以创作
• AI 视频生成器 — 输入提示词，获得专业视频
• AI 虚拟形象和网红 — 超写实数字主播
• UGC 视频广告 — 真实用户风格广告内容
• 节拍同步视频 — 自动与音乐节拍匹配
• 广告制作器 — TikTok、Reels 和 YouTube Shorts 广告

🚀 专为增长而生
• 4K 品质，针对各平台优化
• 直接导出到抖音、Instagram Reels、YouTube Shorts
• 一键切换画面比例 (9:16、1:1、16:9)
• 30+ 语言 AI 配音

🏆 50万+ 创作者信赖之选

免费开始。首个视频无水印。

积分说明
CreatorAI 采用积分制。积分通过应用内购买获得，无需订阅。

隐私政策: https://holylabs.net/privacy""",
        "promotional_text": "全新：AI 虚拟形象工作室 — 几分钟内创建你的数字分身。限时积分包 5 折优惠！",
        "release_notes": "• 全新 AI 虚拟形象工作室 — 超写实数字主播\n• 视频渲染速度最高提升 3 倍\n• 节拍同步改进，支持自动节拍检测\n• 错误修复和性能改进",
    },
    "zh-Hant": {
        "subtitle": "AI影片、虛擬化身和廣告",
        "keywords": "ai影片生成,文字轉影片,ai虛擬化身,影片廣告,ugc影片,ai網紅,節拍同步",
        "description": """將任何想法在幾秒內變成爆款影片 — 無需剪輯技能。

CreatorAI 是面向內容創作者、行銷人員和品牌的領先 AI 影片創作應用。只需輸入文字，即可生成精彩影片、UGC 風格廣告、AI 虛擬化身和社群媒體內容。

🎬 你可以創作
• AI 影片生成器 — 輸入提示詞，獲得專業影片
• AI 虛擬化身和網紅 — 超擬真數位主播
• UGC 影片廣告 — 真實用戶風格廣告內容
• 節拍同步影片 — 自動與音樂節拍配合
• 廣告製作器 — TikTok、Reels 和 YouTube Shorts 廣告

🚀 專為成長而生
• 4K 畫質，針對各平台優化
• 直接匯出到 TikTok、Instagram Reels、YouTube Shorts
• 一鍵切換畫面比例 (9:16、1:1、16:9)
• 30+ 語言 AI 配音

🏆 50萬+ 創作者信賴之選

免費開始。首個影片無浮水印。

點數說明
CreatorAI 採用點數制。點數透過應用程式內購買取得，無需訂閱。

隱私政策: https://holylabs.net/privacy""",
        "promotional_text": "全新：AI 虛擬化身工作室 — 幾分鐘內創建你的數位分身。限時點數包 5 折優惠！",
        "release_notes": "• 全新 AI 虛擬化身工作室 — 超擬真數位主播\n• 影片渲染速度最高提升 3 倍\n• 節拍同步改進，支援自動節拍偵測\n• 錯誤修正和效能改進",
    },
    "it": {
        "subtitle": "Video IA, Avatar e Pubblicità",
        "keywords": "generatore video ia,testo in video,avatar ia,pubblicita video,ugc video,influencer ia,beat sync",
        "description": """Trasforma qualsiasi idea in un video virale in pochi secondi — senza competenze di editing.

CreatorAI è l'app leader per la creazione di video con IA per creator, marketer e brand. Genera video straordinari, annunci stile UGC, avatar IA e contenuti social con un semplice testo.

🎬 COSA PUOI CREARE
• Generatore video IA — scrivi un prompt, ottieni un video professionale
• Avatar e influencer IA — presentatori digitali iperrealisti
• Annunci video UGC — contenuto autentico stile utente
• Video Beat Sync — sincronizza clip con la musica automaticamente
• Creatore di annunci — ads per TikTok, Reels e YouTube Shorts

🚀 PROGETTATO PER LA CRESCITA
• Rendering 4K ottimizzato per ogni piattaforma
• Esporta direttamente su TikTok, Instagram Reels, YouTube Shorts
• Cambio rapporto di aspetto in un tap (9:16, 1:1, 16:9)
• Voce fuori campo IA in 30+ lingue

🏆 SCELTO DA 500K+ CREATOR

Inizia gratis. Nessuna filigrana sul primo video.

INFO CREDITI
CreatorAI usa un sistema a crediti. Acquisti una tantum. Nessun abbonamento richiesto.

Privacy: https://holylabs.net/privacy""",
        "promotional_text": "Nuovo: Studio Avatar IA — crea il tuo gemello digitale in minuti. 50% di sconto sui pacchetti crediti!",
        "release_notes": "• Nuovo Studio Avatar IA — presentatori digitali iperrealisti\n• Rendering video fino a 3× più veloce\n• Miglioramenti Beat Sync con rilevamento automatico del tempo\n• Correzioni di bug e miglioramenti delle prestazioni",
    },
    "nl-NL": {
        "subtitle": "AI Video, Avatars & Advertenties",
        "keywords": "ai videogenerator,tekst naar video,ai avatar,video advertentie,ugc video,ai influencer,beat sync",
        "description": """Verander elk idee in een virale video in seconden — geen montagevaardigheden nodig.

CreatorAI is de toonaangevende AI-video-app voor contentmakers, marketeers en merken. Genereer prachtige video's, UGC-stijl advertenties, AI-avatars en sociale media content vanuit een simpele tekst.

🎬 WAT JE KUNT MAKEN
• AI-videogenerator — typ een prompt, krijg een professionele video
• AI-avatars & influencers — hyperrealistische digitale presentatoren
• UGC-videoadvertenties — authentieke gebruikersstijl content
• Beat Sync-video's — clips automatisch synchroniseren met muziek
• Advertentiemaker — ads voor TikTok, Reels & YouTube Shorts

🚀 GEBOUWD VOOR GROEI
• 4K-kwaliteit geoptimaliseerd voor elk platform
• Direct exporteren naar TikTok, Instagram Reels, YouTube Shorts
• Beeldverhouding in één tik wisselen (9:16, 1:1, 16:9)
• AI-voice-over in 30+ talen

🏆 VERTROUWD DOOR 500K+ MAKERS

Gratis starten. Geen watermerk op de eerste video.

KREDIET INFO
CreatorAI gebruikt een kredietsysteem. Eenmalige aankopen. Geen abonnement vereist.

Privacy: https://holylabs.net/privacy""",
        "promotional_text": "Nieuw: AI Avatar Studio — maak je digitale tweeling in minuten. 50% korting op kredietpakketten!",
        "release_notes": "• Nieuw AI Avatar Studio — hyperrealistische digitale presentatoren\n• Videoverwerking tot 3× sneller\n• Beat Sync verbeteringen met automatische tempodetectie\n• Bugfixes en prestatieverbeteringen",
    },
    "ru": {
        "subtitle": "ИИ видео, аватары и реклама",
        "keywords": "генератор видео ии,текст в видео,аватар ии,видеореклама,ugc видео,ии инфлюенсер,бит синк",
        "description": """Превращай любую идею в вирусное видео за секунды — без навыков монтажа.

CreatorAI — ведущее приложение для создания видео с ИИ для контент-мейкеров, маркетологов и брендов. Генерируй впечатляющие видео, рекламу в стиле UGC, ИИ-аватары и контент для соцсетей из простого текста.

🎬 ЧТО ТЫ МОЖЕШЬ СОЗДАТЬ
• Генератор видео ИИ — введи промпт, получи профессиональное видео
• ИИ-аватары и инфлюенсеры — гиперреалистичные цифровые ведущие
• UGC-видеореклама — аутентичный пользовательский стиль
• Видео с бит-синком — автосинхронизация с музыкой
• Создатель рекламы — ads для TikTok, Reels и YouTube Shorts

🚀 СОЗДАН ДЛЯ РОСТА
• 4K-качество для каждой платформы
• Прямой экспорт в TikTok, Instagram Reels, YouTube Shorts
• Смена соотношения сторон в один тап (9:16, 1:1, 16:9)
• ИИ-озвучка на 30+ языках

🏆 ДОВЕРЯЮТ 500К+ КРЕАТОРОВ

Начни бесплатно. Без водяного знака на первом видео.

О КРЕДИТАХ
CreatorAI использует кредитную систему. Разовые покупки. Подписка не нужна.

Конфиденциальность: https://holylabs.net/privacy""",
        "promotional_text": "Новое: Студия ИИ-аватаров — создай цифрового двойника за минуты. Скидка 50% на пакеты кредитов!",
        "release_notes": "• Новая Студия ИИ-аватаров — гиперреалистичные цифровые ведущие\n• Ускорение рендеринга видео до 3×\n• Улучшения бит-синка с автодетекцией темпа\n• Исправления ошибок и улучшения производительности",
    },
    "tr": {
        "subtitle": "AI Video, Avatar ve Reklam Yapıcı",
        "keywords": "ai video olusturucu,metinden video,ai avatar,video reklam,ugc video,ai influencer,beat sync",
        "description": """Herhangi bir fikri saniyeler içinde viral bir videoya dönüştür — düzenleme becerisine gerek yok.

CreatorAI, içerik üreticileri, pazarlamacılar ve markalar için önde gelen AI video oluşturma uygulamasıdır. Basit bir metinle etkileyici videolar, UGC tarzı reklamlar, AI avatarlar ve sosyal medya içerikleri oluştur.

🎬 NELERİ YAPABİLİRSİN
• AI Video Oluşturucu — prompt yaz, profesyonel video al
• AI Avatar ve Influencer'lar — hiper gerçekçi dijital sunucular
• UGC Video Reklamları — otantik kullanıcı tarzı içerik
• Beat Sync Videolar — klipleri müzikle otomatik senkronize et
• Reklam Yapıcı — TikTok, Reels ve YouTube Shorts için

🚀 BÜYÜME İÇİN TASARLANDI
• Her platform için optimize edilmiş 4K kalite
• TikTok, Instagram Reels, YouTube Shorts'a doğrudan dışa aktar
• Tek dokunuşta en boy oranı değiştirme (9:16, 1:1, 16:9)
• 30+ dilde AI seslendirme

🏆 500BİN+ İÇERİK ÜRETİCİSİNİN TERCİHİ

Ücretsiz başla. İlk videoda filigran yok.

KREDİ BİLGİSİ
CreatorAI kredi sistemi kullanır. Tek seferlik satın alımlar. Abonelik gerekmez.

Gizlilik: https://holylabs.net/privacy""",
        "promotional_text": "Yeni: AI Avatar Stüdyosu — dijital ikizini dakikalar içinde oluştur. Kredi paketlerinde %50 indirim!",
        "release_notes": "• Yeni AI Avatar Stüdyosu — hiper gerçekçi dijital sunucular\n• Video renderlama 3× daha hızlı\n• Otomatik tempo algılamalı Beat Sync iyileştirmeleri\n• Hata düzeltmeleri ve performans iyileştirmeleri",
    },
    "id": {
        "subtitle": "Video AI, Avatar & Pembuat Iklan",
        "keywords": "pembuat video ai,teks ke video,avatar ai,iklan video,ugc video,influencer ai,beat sync",
        "description": """Ubah ide apapun menjadi video viral dalam hitungan detik — tanpa kemampuan editing.

CreatorAI adalah aplikasi pembuatan video AI terdepan untuk kreator konten, pemasar, dan merek. Buat video menakjubkan, iklan gaya UGC, avatar AI, dan konten media sosial hanya dari teks sederhana.

🎬 APA YANG BISA KAMU BUAT
• Generator Video AI — ketik prompt, dapatkan video profesional
• Avatar & Influencer AI — presenter digital hiper-realistis
• Iklan Video UGC — konten otentik gaya pengguna
• Video Beat Sync — sinkronisasi klip ke musik secara otomatis
• Pembuat Iklan — ads untuk TikTok, Reels & YouTube Shorts

🚀 DIRANCANG UNTUK PERTUMBUHAN
• Kualitas 4K dioptimalkan untuk setiap platform
• Ekspor langsung ke TikTok, Instagram Reels, YouTube Shorts
• Ganti rasio aspek dengan satu ketukan (9:16, 1:1, 16:9)
• Voice over AI dalam 30+ bahasa

🏆 DIPERCAYA 500K+ KREATOR

Mulai gratis. Tanpa watermark di video pertama.

INFO KREDIT
CreatorAI menggunakan sistem kredit. Pembelian sekali bayar. Tidak perlu langganan.

Privasi: https://holylabs.net/privacy""",
        "promotional_text": "Baru: Studio Avatar AI — buat kembaran digitalmu dalam hitungan menit. Diskon 50% paket kredit!",
        "release_notes": "• Studio Avatar AI baru — presenter digital hiper-realistis\n• Rendering video hingga 3× lebih cepat\n• Peningkatan Beat Sync dengan deteksi tempo otomatis\n• Perbaikan bug dan peningkatan performa",
    },
    "th": {
        "subtitle": "วิดีโอ AI อวตาร และโฆษณา",
        "keywords": "สร้างวิดีโอ ai,ข้อความเป็นวิดีโอ,อวตาร ai,โฆษณาวิดีโอ,ugc วิดีโอ,อินฟลูเอนเซอร์ ai",
        "description": """เปลี่ยนทุกไอเดียเป็นวิดีโอไวรัลในไม่กี่วินาที — ไม่ต้องมีทักษะตัดต่อ

CreatorAI คือแอปสร้างวิดีโอ AI ชั้นนำสำหรับครีเอเตอร์ นักการตลาด และแบรนด์ สร้างวิดีโอสวยงาม โฆษณาสไตล์ UGC อวตาร AI และคอนเทนต์โซเชียลมีเดียจากข้อความง่ายๆ

🎬 สิ่งที่คุณสร้างได้
• เครื่องสร้างวิดีโอ AI — พิมพ์พรอมต์ รับวิดีโอมืออาชีพ
• อวตาร AI & อินฟลูเอนเซอร์ — พรีเซนเตอร์ดิจิทัลที่สมจริงสูง
• โฆษณาวิดีโอ UGC — คอนเทนต์สไตล์ผู้ใช้จริง
• วิดีโอบีตซิงค์ — ซิงค์คลิปกับเพลงอัตโนมัติ
• เครื่องสร้างโฆษณา — ads สำหรับ TikTok, Reels & YouTube Shorts

🚀 ออกแบบเพื่อการเติบโต
• คุณภาพ 4K สำหรับทุกแพลตฟอร์ม
• ส่งออกตรงไป TikTok, Instagram Reels, YouTube Shorts
• เปลี่ยนอัตราส่วนภาพด้วยแตะเดียว (9:16, 1:1, 16:9)
• AI พากย์เสียงกว่า 30 ภาษา

🏆 ไว้วางใจโดยครีเอเตอร์กว่า 500,000 คน

เริ่มฟรี ไม่มีลายน้ำในวิดีโอแรก

ข้อมูลเครดิต
CreatorAI ใช้ระบบเครดิต ซื้อครั้งเดียว ไม่ต้องสมัครสมาชิก

ความเป็นส่วนตัว: https://holylabs.net/privacy""",
        "promotional_text": "ใหม่: AI Avatar Studio — สร้างตัวตนดิจิทัลของคุณในไม่กี่นาที ลด 50% แพ็กเกจเครดิต!",
        "release_notes": "• AI Avatar Studio ใหม่ — พรีเซนเตอร์ดิจิทัลที่สมจริงสูง\n• เรนเดอร์วิดีโอเร็วขึ้นสูงสุด 3 เท่า\n• ปรับปรุง Beat Sync พร้อมตรวจจับเทมโปอัตโนมัติ\n• แก้ไขบักและปรับปรุงประสิทธิภาพ",
    },
    "vi": {
        "subtitle": "Video AI, Avatar & Nhà Tạo Quảng Cáo",
        "keywords": "tạo video ai,văn bản thành video,avatar ai,quảng cáo video,ugc video,influencer ai,beat sync",
        "description": """Biến bất kỳ ý tưởng nào thành video viral chỉ trong vài giây — không cần kỹ năng chỉnh sửa.

CreatorAI là ứng dụng tạo video AI hàng đầu cho nhà sáng tạo nội dung, marketer và thương hiệu. Tạo video ấn tượng, quảng cáo phong cách UGC, avatar AI và nội dung mạng xã hội từ một đoạn văn bản đơn giản.

🎬 BẠN CÓ THỂ TẠO GÌ
• Bộ tạo video AI — nhập gợi ý, nhận video chuyên nghiệp
• Avatar AI & Influencer — người dẫn chương trình kỹ thuật số siêu thực
• Quảng cáo video UGC — nội dung phong cách người dùng thật
• Video Beat Sync — tự động đồng bộ clip với âm nhạc
• Nhà tạo quảng cáo — ads cho TikTok, Reels & YouTube Shorts

🚀 ĐƯỢC THIẾT KẾ ĐỂ TĂNG TRƯỞNG
• Chất lượng 4K tối ưu cho mọi nền tảng
• Xuất trực tiếp sang TikTok, Instagram Reels, YouTube Shorts
• Chuyển tỷ lệ khung hình bằng một lần chạm (9:16, 1:1, 16:9)
• Lồng tiếng AI trên 30+ ngôn ngữ

🏆 ĐƯỢC TIN TƯỞNG BỞI 500K+ NHÀ SÁNG TẠO

Bắt đầu miễn phí. Không có hình mờ trên video đầu tiên.

THÔNG TIN TÍN DỤNG
CreatorAI sử dụng hệ thống tín dụng. Mua một lần. Không cần đăng ký.

Quyền riêng tư: https://holylabs.net/privacy""",
        "promotional_text": "Mới: AI Avatar Studio — tạo phân thân kỹ thuật số của bạn trong vài phút. Giảm 50% gói tín dụng!",
        "release_notes": "• AI Avatar Studio mới — người dẫn kỹ thuật số siêu thực\n• Kết xuất video nhanh hơn tới 3×\n• Cải tiến Beat Sync với phát hiện nhịp độ tự động\n• Sửa lỗi và cải thiện hiệu suất",
    },
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
        "subtitle": "AI Βίντεο, Άβαταρ και Διαφημίσεις",
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
    print(f"✓ {lang}")

print(f"\nDone! {len(METADATA)} languages written.")
