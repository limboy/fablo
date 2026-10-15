import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("prepare_import", Path(__file__).parents[1] / "scripts/prepare-japanese-import.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)
english_spec = importlib.util.spec_from_file_location("prepare_english_import", Path(__file__).parents[1] / "scripts/prepare-english-import.py")
english = importlib.util.module_from_spec(english_spec)
english_spec.loader.exec_module(english)


class PreparationTests(unittest.TestCase):
    def test_manifest_japanese_wins_over_translated_or_abbreviated_subtitles(self):
        self.assertEqual(adapter.display_sentence({"text": "一緒に遊んでもいいですか。", "subtitle": "私：可以一起玩吗？"}), "一緒に遊んでもいいですか。")
        self.assertEqual(adapter.display_sentence({"text": "受付の人が「待ってください」と言いました。", "subtitle": "受付：待ってください。"}), "受付の人が「待ってください」と言いました。")
        self.assertEqual(adapter.display_sentence({"text": "すみません。", "subtitle": "私：「すみません。」"}), "私：すみません。")

    def test_estimated_words_stay_inside_fractional_sentence_boundaries(self):
        sentences = [{"c": [{"w": [{"s": "私", "r": "わたし"}, {"s": "です", "r": ""}, {"s": "。", "r": ""}]}]}]
        result = adapter.timeline(sentences, [[True, True, False]], [(60 + 5.491, 60 + 8.061)], 70)
        previous = result["sentenceStarts"][0]
        for time in result["wordStarts"][0]:
            if time is not None:
                self.assertGreaterEqual(time, previous)
                self.assertLessEqual(time, result["sentenceEnds"][0])
                previous = time
        self.assertIsNone(result["wordStarts"][0][-1])
        self.assertFalse(result["isAligned"])

    def test_english_contractions_hyphens_and_decimal_numbers_stay_readable(self):
        text = "We don't need 1,000 followers or a one-size-fits-all plan for $3.50."
        tokens = [m[0] for m in english.TOKEN.finditer(text)]
        self.assertIn("don't", tokens)
        self.assertIn("one-size-fits-all", tokens)
        self.assertIn("1,000", tokens)
        self.assertIn("3.50", tokens)
        self.assertEqual("".join(tokens), text.replace(" ", ""))

    def test_english_vocabulary_table_keeps_phrase_glosses(self):
        glossary = english.vocabulary("## Vocabulary\n\n| Item | Meaning |\n|---|---|\n| suspended platform | 悬吊平台 |\n\n## 中文梗概\n正文\n")
        self.assertEqual(glossary, {"suspended platform": "悬吊平台"})
        self.assertEqual(english.vocabulary("## Vocabulary\n| English | 中文 |\n|---|---|\n| facade | 建筑外立面 |\n"), {"facade": "建筑外立面"})


if __name__ == "__main__":
    unittest.main()
