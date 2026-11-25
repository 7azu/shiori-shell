# Read tab: Latin transliteration for scripts the reader shows a second line for.

import re

TRANSLIT = {
    # Cyrillic (Russian, plus Ukrainian/Belarusian/Serbian/Bulgarian letters), simple English-style spelling
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "zh", "з": "z", "и": "i", "й": "y",
    "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
    "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu",
    "я": "ya", "і": "i", "ї": "yi", "є": "ye", "ґ": "g", "ў": "w", "ј": "j", "љ": "lj", "њ": "nj", "ћ": "ć",
    "ђ": "đ", "џ": "dž",
    # Greek (modern, simple)
    "α": "a", "ά": "a", "β": "v", "γ": "g", "δ": "d", "ε": "e", "έ": "e", "ζ": "z", "η": "i", "ή": "i", "θ": "th",
    "ι": "i", "ί": "i", "ϊ": "i", "ΐ": "i", "κ": "k", "λ": "l", "μ": "m", "ν": "n", "ξ": "x", "ο": "o", "ό": "o",
    "π": "p", "ρ": "r", "σ": "s", "ς": "s", "τ": "t", "υ": "y", "ύ": "y", "ϋ": "y", "ΰ": "y", "φ": "f", "χ": "ch",
    "ψ": "ps", "ω": "o", "ώ": "o",
}
TRANSLIT_RE = re.compile("[%s]" % "".join(TRANSLIT), re.I)


def translit(text):
    """Latin transliteration for scripts the reader shows a second line for; "" for everything else."""
    if not TRANSLIT_RE.search(text):
        return ""
    out = []
    for c in text:
        low = c.lower()
        if low in TRANSLIT:
            t = TRANSLIT[low]
            out.append(t.capitalize() if c != low else t)
        else:
            out.append(c)
    return "".join(out)
