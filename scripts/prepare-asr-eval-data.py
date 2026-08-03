#!/usr/bin/env python3
"""Build the ASR eval set from LibriSpeech test-clean.

Buckets:
  short   individual utterances 2-8s      x20
  medium  individual utterances 8-20s     x20
  long    same-chapter concatenations ~60s x8
  xlong   same-chapter concatenations ~150s x4

Every output file is converted to 48kHz mono 16-bit WAV (mic-like input) via
afconvert. References come from the chapter .trans.txt files.
"""

import json
import os
import struct
import subprocess
import sys
import wave

ROOT = os.path.dirname(os.path.abspath(__file__))
LS = os.path.join(ROOT, "LibriSpeech", "test-clean")
OUT = os.path.join(ROOT, "data")
os.makedirs(OUT, exist_ok=True)


def flac_duration(path):
    out = subprocess.run(
        ["afinfo", path], capture_output=True, text=True, check=True
    ).stdout
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("estimated duration:"):
            return float(line.split(":")[1].strip().split()[0])
    raise RuntimeError(f"no duration in afinfo for {path}")


def load_transcripts():
    """Return list of (utterance_id, flac_path, text, duration) grouped by chapter."""
    chapters = []
    for speaker in sorted(os.listdir(LS)):
        sdir = os.path.join(LS, speaker)
        if not os.path.isdir(sdir):
            continue
        for chapter in sorted(os.listdir(sdir)):
            cdir = os.path.join(sdir, chapter)
            trans = os.path.join(cdir, f"{speaker}-{chapter}.trans.txt")
            if not os.path.exists(trans):
                continue
            utterances = []
            with open(trans) as fh:
                for line in fh:
                    utt_id, text = line.strip().split(" ", 1)
                    flac = os.path.join(cdir, f"{utt_id}.flac")
                    if os.path.exists(flac):
                        utterances.append((utt_id, flac, text))
            if utterances:
                chapters.append(utterances)
    return chapters


def to_wav16(flac, wav):
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", flac, wav],
        check=True, capture_output=True,
    )


def upsample48(wav16, wav48):
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", "LEI16@48000", "--src-complexity", "bats",
         wav16, wav48],
        check=True, capture_output=True,
    )


def concat_wavs(paths, out_path):
    data = b""
    params = None
    for p in paths:
        with wave.open(p, "rb") as w:
            if params is None:
                params = w.getparams()
            data += w.readframes(w.getnframes())
    with wave.open(out_path, "wb") as w:
        w.setparams(params)
        w.writeframes(data)


def main():
    chapters = load_transcripts()
    rng_chapters = chapters[:]  # deterministic order

    manifest = []
    used_chapters = set()

    # Individual utterance buckets: walk chapters round-robin for diversity.
    short_needed, medium_needed = 20, 20
    for ci, utterances in enumerate(rng_chapters):
        if short_needed == 0 and medium_needed == 0:
            break
        for utt_id, flac, text in utterances:
            if short_needed == 0 and medium_needed == 0:
                break
            dur = flac_duration(flac)
            bucket = None
            if 2 <= dur <= 8 and short_needed > 0:
                bucket, short_needed = "short", short_needed - 1
            elif 8 < dur <= 20 and medium_needed > 0:
                bucket, medium_needed = "medium", medium_needed - 1
            if bucket is None:
                continue
            used_chapters.add(ci)
            wav16 = os.path.join(OUT, f"{utt_id}.16k.wav")
            wav48 = os.path.join(OUT, f"{utt_id}.wav")
            to_wav16(flac, wav16)
            upsample48(wav16, wav48)
            os.remove(wav16)
            manifest.append(
                {"id": utt_id, "audio": f"data/{utt_id}.wav",
                 "reference": text, "bucket": bucket}
            )
            break  # at most one utterance per chapter for diversity

    # Concatenated buckets from chapters not already sampled.
    def build_concat(bucket, target_seconds, count, start_index):
        built = 0
        for ci in range(start_index, len(rng_chapters)):
            if built == count:
                break
            if ci in used_chapters:
                continue
            utterances = rng_chapters[ci]
            picked, total, texts = [], 0.0, []
            for utt_id, flac, text in utterances:
                dur = flac_duration(flac)
                picked.append((utt_id, flac))
                texts.append(text)
                total += dur
                if total >= target_seconds:
                    break
            if total < target_seconds * 0.8:
                continue
            used_chapters.add(ci)
            name = f"{bucket}-{picked[0][0]}"
            wav16s = []
            for utt_id, flac in picked:
                wav16 = os.path.join(OUT, f"{utt_id}.c16k.wav")
                to_wav16(flac, wav16)
                wav16s.append(wav16)
            merged16 = os.path.join(OUT, f"{name}.16k.wav")
            concat_wavs(wav16s, merged16)
            for w in wav16s:
                os.remove(w)
            wav48 = os.path.join(OUT, f"{name}.wav")
            upsample48(merged16, wav48)
            os.remove(merged16)
            manifest.append(
                {"id": name, "audio": f"data/{name}.wav",
                 "reference": " ".join(texts), "bucket": bucket}
            )
            built += 1
        if built < count:
            print(f"warning: only built {built}/{count} for {bucket}", file=sys.stderr)

    build_concat("long", 60, 8, 0)
    build_concat("xlong", 150, 4, 0)

    with open(os.path.join(ROOT, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2)
    counts = {}
    total_s = 0.0
    for entry in manifest:
        counts[entry["bucket"]] = counts.get(entry["bucket"], 0) + 1
    print(f"manifest: {len(manifest)} files, buckets={counts}")


if __name__ == "__main__":
    main()
