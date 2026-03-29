import Foundation

/// Generates video scripts locally without any backend/API calls.
/// Uses template-based generation with smart keyword extraction.
/// Direct port of Android LocalScriptGenerator.
struct LocalScriptGenerator {

    struct SceneScript {
        let searchQuery: String
        let subtitleText: String
        let voiceoverText: String
        let durationSeconds: Double
    }

    struct GeneratedScript {
        let topic: String
        let scenes: [SceneScript]
        let fullVoiceover: String
        let totalDuration: Double
    }

    // MARK: - Hook templates

    private static let hookTemplates: [String: [String]] = [
        "en": [
            "Stop scrolling. This changes everything.",
            "Nobody talks about this, but...",
            "Here's what they don't tell you about {topic}.",
            "POV: You just discovered {topic}.",
            "Wait for it... {topic} is not what you think.",
            "This is your sign to {topic}.",
            "The truth about {topic} that nobody shares.",
            "You've been doing {topic} wrong this whole time."
        ],
        "ru": [
            "Stop. This changes everything.",
            "Nobody talks about this, but...",
            "Here's what they don't tell you about {topic}.",
            "POV: You just discovered {topic}."
        ],
        "es": [
            "Deja de scrollear. Esto cambia todo.",
            "Nadie habla de esto, pero...",
            "Lo que no te dicen sobre {topic}.",
            "POV: Acabas de descubrir {topic}."
        ],
        "de": [
            "Scrolle nicht weiter. Das ist wichtig.",
            "Niemand spricht daruber, aber...",
            "Was sie dir uber {topic} nicht sagen.",
            "POV: Du hast gerade {topic} entdeckt."
        ],
        "fr": [
            "Arretez de scroller. Ca change tout.",
            "Personne n'en parle, mais...",
            "Ce qu'on ne vous dit pas sur {topic}.",
            "POV: Vous venez de decouvrir {topic}."
        ],
        "pt": [
            "Para de rolar. Isso muda tudo.",
            "Ninguem fala sobre isso, mas...",
            "O que nao te contam sobre {topic}.",
            "POV: Voce acabou de descobrir {topic}."
        ],
        "he": [
            "\u{05EA}\u{05E4}\u{05E1}\u{05D9}\u{05E7}\u{05D5} \u{05DC}\u{05D2}\u{05DC}\u{05D5}\u{05DC}. \u{05D6}\u{05D4} \u{05DE}\u{05E9}\u{05E0}\u{05D4} \u{05D4}\u{05DB}\u{05DC}.",
            "\u{05D0}\u{05E3} \u{05D0}\u{05D7}\u{05D3} \u{05DC}\u{05D0} \u{05DE}\u{05D3}\u{05D1}\u{05E8} \u{05E2}\u{05DC} \u{05D6}\u{05D4}, \u{05D0}\u{05D1}\u{05DC}...",
            "\u{05DE}\u{05D4} \u{05E9}\u{05DC}\u{05D0} \u{05D0}\u{05D5}\u{05DE}\u{05E8}\u{05D9}\u{05DD} \u{05DC}\u{05DA} \u{05E2}\u{05DC} {topic}.",
            "POV: \u{05D6}\u{05D4} \u{05E2}\u{05EA}\u{05D4} \u{05D2}\u{05D9}\u{05DC}\u{05D9}\u{05EA} \u{05D0}\u{05EA} {topic}."
        ]
    ]

    // MARK: - CTA templates

    private static let ctaTemplates: [String: [String]] = [
        "en": [
            "Follow for more.",
            "Save this for later.",
            "Share this with someone who needs it.",
            "Don't miss the next one. Follow now.",
            "Tag someone who needs to see this."
        ],
        "ru": ["Podpisyvaysya.", "Sokhrani na potom.", "Podelis s druzyami."],
        "es": ["Sigueme para mas.", "Guarda esto.", "Comparte con alguien."],
        "de": ["Folge fur mehr.", "Speichere das.", "Teile es mit jemandem."],
        "fr": ["Suivez pour plus.", "Sauvegardez ceci.", "Partagez avec quelqu'un."],
        "pt": ["Siga para mais.", "Salve isso.", "Compartilhe com alguem."],
        "he": ["\u{05E2}\u{05E7}\u{05D1}\u{05D5} \u{05DC}\u{05E2}\u{05D5}\u{05D3}.", "\u{05E9}\u{05DE}\u{05E8}\u{05D5} \u{05D0}\u{05EA} \u{05D6}\u{05D4}.", "\u{05E9}\u{05EA}\u{05E4}\u{05D5} \u{05E2}\u{05DD} \u{05DE}\u{05D9}\u{05E9}\u{05D4}\u{05D5}."]
    ]

    // MARK: - Content phrase templates

    private static let contentTemplates: [String: [String]] = [
        "en": [
            "The key to {kw} is consistency.",
            "Most people overlook {kw}.",
            "{kw} can transform your life.",
            "Here's the secret about {kw}.",
            "This is why {kw} matters.",
            "Think about {kw} differently.",
            "The real power of {kw}.",
            "What makes {kw} so effective."
        ],
        "es": [
            "La clave de {kw} es la constancia.",
            "La mayoria ignora {kw}.",
            "{kw} puede transformar tu vida.",
            "Este es el secreto de {kw}."
        ],
        "ru": [
            "Klyuch k {kw} - postoyanstvo.",
            "Bolshinstvo lyudey ignoriruyut {kw}.",
            "{kw} mozhet izmenit vashu zhizn.",
            "Vot sekret {kw}."
        ],
        "de": [
            "Der Schlussel zu {kw} ist Bestandigkeit.",
            "Die meisten ubersehen {kw}.",
            "{kw} kann dein Leben verandern.",
            "Das Geheimnis von {kw}."
        ],
        "fr": [
            "La cle de {kw} est la regularite.",
            "La plupart des gens ignorent {kw}.",
            "{kw} peut transformer votre vie.",
            "Le secret de {kw}."
        ],
        "pt": [
            "A chave para {kw} e consistencia.",
            "A maioria ignora {kw}.",
            "{kw} pode transformar sua vida.",
            "O segredo de {kw}."
        ],
        "he": [
            "\u{05D4}\u{05DE}\u{05E4}\u{05EA}\u{05D7} \u{05DC}{kw} \u{05D4}\u{05D5}\u{05D0} \u{05E2}\u{05E7}\u{05D1}\u{05D9}\u{05D5}\u{05EA}.",
            "\u{05E8}\u{05D5}\u{05D1} \u{05D4}\u{05D0}\u{05E0}\u{05E9}\u{05D9}\u{05DD} \u{05DE}\u{05EA}\u{05E2}\u{05DC}\u{05DE}\u{05D9}\u{05DD} \u{05DE}{kw}.",
            "{kw} \u{05D9}\u{05DB}\u{05D5}\u{05DC} \u{05DC}\u{05E9}\u{05E0}\u{05D5}\u{05EA} \u{05D0}\u{05EA} \u{05D4}\u{05D7}\u{05D9}\u{05D9}\u{05DD} \u{05E9}\u{05DC}\u{05DA}.",
            "\u{05D4}\u{05E1}\u{05D5}\u{05D3} \u{05E9}\u{05DC} {kw}."
        ]
    ]

    // MARK: - Public API

    static func generateScript(
        topic: String,
        language: String = "en",
        clipCount: Int = 6,
        durationPerClip: Double = 2.5
    ) -> GeneratedScript {
        let keywords = extractKeywords(topic)
        let hooks = hookTemplates[language] ?? hookTemplates["en"]!
        let ctas = ctaTemplates[language] ?? ctaTemplates["en"]!

        var scenes: [SceneScript] = []

        // Scene 1: Hook
        let hook = hooks.randomElement()!.replacingOccurrences(of: "{topic}", with: String(topic.prefix(30)))
        scenes.append(SceneScript(
            searchQuery: keywords.first ?? topic,
            subtitleText: hook,
            voiceoverText: hook,
            durationSeconds: durationPerClip
        ))

        // Middle scenes: content points
        let contentScenes = generateContentPoints(topic: topic, keywords: keywords, language: language, count: clipCount - 2)
        scenes.append(contentsOf: contentScenes)

        // Last scene: CTA
        let cta = ctas.randomElement()!
        scenes.append(SceneScript(
            searchQuery: keywords.last ?? "inspiration motivation",
            subtitleText: cta,
            voiceoverText: cta,
            durationSeconds: durationPerClip
        ))

        let fullVoiceover = scenes.map(\.voiceoverText).joined(separator: " ")

        return GeneratedScript(
            topic: topic,
            scenes: scenes,
            fullVoiceover: fullVoiceover,
            totalDuration: scenes.reduce(0) { $0 + $1.durationSeconds }
        )
    }

    // MARK: - Private helpers

    private static func generateContentPoints(topic: String, keywords: [String], language: String, count: Int) -> [SceneScript] {
        let searchQueries = generateSearchQueries(topic: topic, keywords: keywords, count: count)
        let contentPhrases = generateContentPhrases(topic: topic, keywords: keywords, language: language, count: count)

        return (0..<count).map { i in
            SceneScript(
                searchQuery: i < searchQueries.count ? searchQueries[i] : (keywords.randomElement() ?? topic),
                subtitleText: i < contentPhrases.count ? contentPhrases[i] : topic,
                voiceoverText: i < contentPhrases.count ? contentPhrases[i] : topic,
                durationSeconds: 2.5
            )
        }
    }

    private static func generateSearchQueries(topic: String, keywords: [String], count: Int) -> [String] {
        let modifiers = [
            "cinematic", "aerial view", "close up", "lifestyle",
            "professional", "modern", "urban", "nature",
            "technology", "people working", "success", "creative"
        ]

        var queries: [String] = []

        for kw in keywords where queries.count < count {
            queries.append(kw)
        }

        for kw in keywords {
            for mod in modifiers.shuffled() where queries.count < count {
                queries.append("\(kw) \(mod)")
            }
        }

        while queries.count < count {
            let prefix = topic.split(separator: " ").prefix(2).joined(separator: " ")
            queries.append("\(prefix) \(modifiers.randomElement()!)")
        }

        return Array(queries.prefix(count))
    }

    private static func generateContentPhrases(topic: String, keywords: [String], language: String, count: Int) -> [String] {
        let templates = contentTemplates[language] ?? contentTemplates["en"]!
        let shuffled = templates.shuffled()
        let topicWords = topic.split(separator: " ").filter { $0.count > 3 }.map(String.init)

        return (0..<count).map { i in
            let template = shuffled[i % shuffled.count]
            let kw: String
            if i < keywords.count {
                kw = keywords[i]
            } else if !topicWords.isEmpty {
                kw = topicWords[i % topicWords.count]
            } else {
                kw = String(topic.prefix(20))
            }
            return template.replacingOccurrences(of: "{kw}", with: kw)
        }
    }

    /// Extract meaningful keywords from a topic string for Pexels search.
    private static func extractKeywords(_ topic: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "can", "shall", "to", "of", "in", "for",
            "on", "with", "at", "by", "from", "as", "into", "about", "between",
            "through", "after", "before", "during", "without", "again", "further",
            "then", "once", "here", "there", "when", "where", "why", "how", "all",
            "each", "every", "both", "few", "more", "most", "other", "some", "such",
            "no", "nor", "not", "only", "own", "same", "so", "than", "too", "very",
            "just", "because", "but", "and", "or", "if", "while", "this", "that",
            "these", "those", "i", "me", "my", "we", "our", "you", "your", "it"
        ]

        let cleaned = topic.lowercased().replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
        let words = cleaned.split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        let unique = Array(NSOrderedSet(array: words)) as! [String]

        // Create bigrams
        var bigrams: [String] = []
        for i in 0..<max(0, unique.count - 1) {
            bigrams.append("\(unique[i]) \(unique[i + 1])")
        }

        return Array((bigrams + unique).prefix(8))
    }
}
