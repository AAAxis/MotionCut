package com.theholylabs.creator.services

import android.util.Log

/**
 * Generates video scripts locally without any backend/API calls.
 * Uses template-based generation with smart keyword extraction.
 *
 * When Google AI Edge (Gemini Nano) becomes widely available,
 * this can be upgraded to use on-device LLM for better quality.
 */
object LocalScriptGenerator {

    private val hookTemplates = mapOf(
        "en" to listOf(
            "Stop scrolling. This changes everything.",
            "Nobody talks about this, but...",
            "Here's what they don't tell you about {topic}.",
            "POV: You just discovered {topic}.",
            "Wait for it... {topic} is not what you think.",
            "This is your sign to {topic}.",
            "The truth about {topic} that nobody shares.",
            "You've been doing {topic} wrong this whole time."
        ),
        "ru" to listOf(
            "Stop. This changes everything.",
            "Nobody talks about this, but...",
            "Here's what they don't tell you about {topic}.",
            "POV: You just discovered {topic}."
        ),
        "es" to listOf(
            "Deja de scrollear. Esto cambia todo.",
            "Nadie habla de esto, pero...",
            "Lo que no te dicen sobre {topic}.",
            "POV: Acabas de descubrir {topic}."
        ),
        "de" to listOf(
            "Scrolle nicht weiter. Das ist wichtig.",
            "Niemand spricht daruber, aber...",
            "Was sie dir uber {topic} nicht sagen.",
            "POV: Du hast gerade {topic} entdeckt."
        ),
        "fr" to listOf(
            "Arretez de scroller. Ca change tout.",
            "Personne n'en parle, mais...",
            "Ce qu'on ne vous dit pas sur {topic}.",
            "POV: Vous venez de decouvrir {topic}."
        ),
        "pt" to listOf(
            "Para de rolar. Isso muda tudo.",
            "Ninguem fala sobre isso, mas...",
            "O que nao te contam sobre {topic}.",
            "POV: Voce acabou de descobrir {topic}."
        ),
        "he" to listOf(
            "\u05EA\u05E4\u05E1\u05D9\u05E7\u05D5 \u05DC\u05D2\u05DC\u05D5\u05DC. \u05D6\u05D4 \u05DE\u05E9\u05E0\u05D4 \u05D4\u05DB\u05DC.",
            "\u05D0\u05E3 \u05D0\u05D7\u05D3 \u05DC\u05D0 \u05DE\u05D3\u05D1\u05E8 \u05E2\u05DC \u05D6\u05D4, \u05D0\u05D1\u05DC...",
            "\u05DE\u05D4 \u05E9\u05DC\u05D0 \u05D0\u05D5\u05DE\u05E8\u05D9\u05DD \u05DC\u05DA \u05E2\u05DC {topic}.",
            "POV: \u05D6\u05D4 \u05E2\u05EA\u05D4 \u05D2\u05D9\u05DC\u05D9\u05EA \u05D0\u05EA {topic}."
        )
    )

    private val ctaTemplates = mapOf(
        "en" to listOf(
            "Follow for more.",
            "Save this for later.",
            "Share this with someone who needs it.",
            "Don't miss the next one. Follow now.",
            "Tag someone who needs to see this."
        ),
        "ru" to listOf("Podpisyvaysya.", "Sokhrani na potom.", "Podelis s druzyami."),
        "es" to listOf("Sigueme para mas.", "Guarda esto.", "Comparte con alguien."),
        "de" to listOf("Folge fur mehr.", "Speichere das.", "Teile es mit jemandem."),
        "fr" to listOf("Suivez pour plus.", "Sauvegardez ceci.", "Partagez avec quelqu'un."),
        "pt" to listOf("Siga para mais.", "Salve isso.", "Compartilhe com alguem."),
        "he" to listOf("\u05E2\u05E7\u05D1\u05D5 \u05DC\u05E2\u05D5\u05D3.", "\u05E9\u05DE\u05E8\u05D5 \u05D0\u05EA \u05D6\u05D4.", "\u05E9\u05EA\u05E4\u05D5 \u05E2\u05DD \u05DE\u05D9\u05E9\u05D4\u05D5.")
    )

    /**
     * Generate a structured video script from a user prompt.
     * Returns a list of scenes with search queries, subtitles, and voiceover text.
     */
    fun generateScript(
        topic: String,
        language: String = "en",
        clipCount: Int = 6,
        durationPerClip: Double = 2.5
    ): GeneratedScript {
        val keywords = extractKeywords(topic)
        val hooks = hookTemplates[language] ?: hookTemplates["en"]!!
        val ctas = ctaTemplates[language] ?: ctaTemplates["en"]!!

        val scenes = mutableListOf<SceneScript>()

        // Scene 1: Hook
        val hook = hooks.random().replace("{topic}", topic.take(30))
        scenes.add(
            SceneScript(
                searchQuery = keywords.firstOrNull() ?: topic,
                subtitleText = hook,
                voiceoverText = hook,
                durationSeconds = durationPerClip
            )
        )

        // Middle scenes: content points
        val contentPoints = generateContentPoints(topic, keywords, language, clipCount - 2)
        scenes.addAll(contentPoints)

        // Last scene: CTA
        val cta = ctas.random()
        scenes.add(
            SceneScript(
                searchQuery = keywords.lastOrNull() ?: "inspiration motivation",
                subtitleText = cta,
                voiceoverText = cta,
                durationSeconds = durationPerClip
            )
        )

        val fullVoiceover = scenes.joinToString(" ") { it.voiceoverText }

        return GeneratedScript(
            topic = topic,
            scenes = scenes,
            fullVoiceover = fullVoiceover,
            totalDuration = scenes.sumOf { it.durationSeconds }
        )
    }

    private fun generateContentPoints(
        topic: String,
        keywords: List<String>,
        language: String,
        count: Int
    ): List<SceneScript> {
        // Generate varied search queries from the topic
        val searchQueries = generateSearchQueries(topic, keywords, count)

        // Generate subtitle/voiceover pairs for each scene
        val contentPhrases = generateContentPhrases(topic, keywords, language, count)

        return (0 until count).map { i ->
            SceneScript(
                searchQuery = searchQueries.getOrElse(i) { keywords.random() },
                subtitleText = contentPhrases.getOrElse(i) { topic },
                voiceoverText = contentPhrases.getOrElse(i) { topic },
                durationSeconds = 2.5
            )
        }
    }

    private fun generateSearchQueries(topic: String, keywords: List<String>, count: Int): List<String> {
        // Combine keywords with cinematic/stock-footage-friendly modifiers
        val modifiers = listOf(
            "cinematic", "aerial view", "close up", "lifestyle",
            "professional", "modern", "urban", "nature",
            "technology", "people working", "success", "creative"
        )

        val queries = mutableListOf<String>()

        // Use direct keywords first
        keywords.forEach { kw ->
            if (queries.size < count) {
                queries.add(kw)
            }
        }

        // Then combine with modifiers
        keywords.forEach { kw ->
            modifiers.shuffled().forEach { mod ->
                if (queries.size < count) {
                    queries.add("$kw $mod")
                }
            }
        }

        // Fill remaining with topic variations
        while (queries.size < count) {
            queries.add("${topic.split(" ").take(2).joinToString(" ")} ${modifiers.random()}")
        }

        return queries.take(count)
    }

    private fun generateContentPhrases(
        topic: String,
        keywords: List<String>,
        language: String,
        count: Int
    ): List<String> {
        // Template-based content generation per language
        val templates = when (language) {
            "en" -> listOf(
                "The key to {kw} is consistency.",
                "Most people overlook {kw}.",
                "{kw} can transform your life.",
                "Here's the secret about {kw}.",
                "This is why {kw} matters.",
                "Think about {kw} differently.",
                "The real power of {kw}.",
                "What makes {kw} so effective."
            )
            "es" -> listOf(
                "La clave de {kw} es la constancia.",
                "La mayoria ignora {kw}.",
                "{kw} puede transformar tu vida.",
                "Este es el secreto de {kw}."
            )
            "ru" -> listOf(
                "Klyuch k {kw} - postoyanstvo.",
                "Bolshinstvo lyudey ignoriruyut {kw}.",
                "{kw} mozhet izmenit vashu zhizn.",
                "Vot sekret {kw}."
            )
            "de" -> listOf(
                "Der Schlussel zu {kw} ist Bestandigkeit.",
                "Die meisten ubersehen {kw}.",
                "{kw} kann dein Leben verandern.",
                "Das Geheimnis von {kw}."
            )
            "fr" -> listOf(
                "La cle de {kw} est la regularite.",
                "La plupart des gens ignorent {kw}.",
                "{kw} peut transformer votre vie.",
                "Le secret de {kw}."
            )
            "pt" -> listOf(
                "A chave para {kw} e consistencia.",
                "A maioria ignora {kw}.",
                "{kw} pode transformar sua vida.",
                "O segredo de {kw}."
            )
            "he" -> listOf(
                "\u05D4\u05DE\u05E4\u05EA\u05D7 \u05DC{kw} \u05D4\u05D5\u05D0 \u05E2\u05E7\u05D1\u05D9\u05D5\u05EA.",
                "\u05E8\u05D5\u05D1 \u05D4\u05D0\u05E0\u05E9\u05D9\u05DD \u05DE\u05EA\u05E2\u05DC\u05DE\u05D9\u05DD \u05DE{kw}.",
                "{kw} \u05D9\u05DB\u05D5\u05DC \u05DC\u05E9\u05E0\u05D5\u05EA \u05D0\u05EA \u05D4\u05D7\u05D9\u05D9\u05DD \u05E9\u05DC\u05DA.",
                "\u05D4\u05E1\u05D5\u05D3 \u05E9\u05DC {kw}."
            )
            else -> listOf("The key to {kw} is consistency.", "{kw} matters more than you think.")
        }

        val phrases = mutableListOf<String>()
        val shuffledTemplates = templates.shuffled()
        val topicWords = topic.split(" ").filter { it.length > 3 }

        for (i in 0 until count) {
            val template = shuffledTemplates[i % shuffledTemplates.size]
            val kw = if (i < keywords.size) keywords[i]
                     else topicWords.getOrElse(i % maxOf(1, topicWords.size)) { topic.take(20) }
            phrases.add(template.replace("{kw}", kw))
        }

        return phrases
    }

    /**
     * Extract meaningful keywords from a topic string for Pexels search.
     */
    private fun extractKeywords(topic: String): List<String> {
        val stopWords = setOf(
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
        )

        val words = topic.lowercase()
            .replace(Regex("[^a-z0-9\\s]"), "")
            .split("\\s+".toRegex())
            .filter { it.length > 2 && it !in stopWords }
            .distinct()

        // Also create bigrams for better search results
        val bigrams = mutableListOf<String>()
        for (i in 0 until words.size - 1) {
            bigrams.add("${words[i]} ${words[i + 1]}")
        }

        return (bigrams + words).take(8)
    }
}

data class GeneratedScript(
    val topic: String,
    val scenes: List<SceneScript>,
    val fullVoiceover: String,
    val totalDuration: Double
)
