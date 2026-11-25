"""Shared parts of the Read tab scripts (jp_library.py, jp_subs.py).

  base      Reader language, folders, JSON-lines output, JSON files, downloads.
  ja_text   Japanese: furigana markup {kanji|reading}, rōmaji, readings of numbers and counters.
  translit  Latin transliteration for Cyrillic and Greek.
  book      Paragraphs -> sentences -> a book as JSON (books/<id>.json + index.json).
  parsers   Book files: EPUB, PDF, TXT, Aozora format.
  catalog   Aozora Bunko catalog, ISBN lookup, covers.

The scripts import the package through their own folder (sys.path). What is a command of a script
(import, scan, translate ...) stays in the script.
"""
