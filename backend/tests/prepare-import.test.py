import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("prepare_import", Path(__file__).parents[1] / "scripts/prepare-japanese-import.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


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


if __name__ == "__main__":
    unittest.main()
