#!/usr/bin/env python3
"""Render timestamped, real console events as a clearly labelled MP4 replay."""
from __future__ import annotations

import argparse
from collections import deque
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap

from PIL import Image, ImageDraw, ImageFont


ANSI = re.compile(r"\x1b\][^\x07]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]")
WIDTH, HEIGHT = 1920, 1080
BG, PANEL, TEXT = "#0a101b", "#111b2a", "#dce7f4"
MUTED, CYAN, GREEN, AMBER, RED = "#90a4bd", "#60d8ef", "#91e2b4", "#f4ce87", "#ff9da7"


@dataclass
class Event:
    t: float
    text: str
    milestone: str = ""


def stamp(seconds: float) -> str:
    milliseconds = round(seconds * 1000)
    hours, remainder = divmod(milliseconds, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    seconds, milliseconds = divmod(remainder, 1000)
    if hours:
        return f"{hours:02}:{minutes:02}:{seconds:02}.{milliseconds:03}"
    return f"{minutes:02}:{seconds:02}.{milliseconds:03}"


def clean_console(text: str) -> str:
    text = ANSI.sub("", text).replace("\r\n", "\n")
    # A carriage return overwrites the current terminal line. Keep its final state.
    text = "\n".join(line.split("\r")[-1] for line in text.split("\n"))
    return "".join(ch for ch in text if ch in "\n\t" or ord(ch) >= 32).expandtabs(4)


def read_events(path: Path) -> list[Event]:
    result = []
    for number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
            if not isinstance(value["text"], str):
                raise ValueError("text must be a string")
            t = float(value["t"])
            if not math.isfinite(t) or t < 0:
                raise ValueError("t must be finite and nonnegative")
            if result and t < result[-1].t:
                raise ValueError("timestamps must be nondecreasing")
            milestone = value.get("milestone", "")
            if not isinstance(milestone, str):
                raise ValueError("milestone must be a string")
            result.append(Event(t, clean_console(value["text"]), clean_console(milestone)))
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            raise ValueError(f"{path}:{number}: {error}") from error
    if not result:
        raise ValueError("The input has no console events")
    return result


def find_font(requested: str | None, bold: bool = False) -> str:
    candidates = [requested] if requested else []
    candidates += [
        str(Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts" / ("consolab.ttf" if bold else "consola.ttf")),
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    raise FileNotFoundError("A monospace TrueType font is required; supply --font")


def line_color(text: str) -> str:
    if re.search(r"\b(error|failed|failure|exception|traceback)\b", text, re.I):
        return RED
    if re.search(r"\b(warning|warn)\b", text, re.I):
        return AMBER
    if re.search(r"\b(pass|passed|success|successful|accepted)\b", text, re.I):
        return GREEN
    if re.search(r"\b(sbom|uam|adi|risk|risks)\b", text, re.I):
        return CYAN
    return TEXT


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("events", type=Path, help="JSONL objects: t, text, optional milestone")
    parser.add_argument("output", type=Path, help="Output .mp4 path")
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"), help="FFmpeg executable")
    parser.add_argument("--title", default="UC1  |  ACRAM console")
    parser.add_argument("--font", help="Monospace TrueType font")
    parser.add_argument("--font-size", type=int, default=26)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--max-gap", type=float, default=2.0, help="Maximum replay seconds per idle gap; 0 preserves all gaps")
    parser.add_argument("--min-hold", type=float, default=0.55, help="Minimum seconds to display each new group of lines")
    parser.add_argument("--lines-per-step", type=int, default=3)
    parser.add_argument("--end-hold", type=float, default=5.0)
    args = parser.parse_args()
    if not args.ffmpeg:
        parser.error("FFmpeg was not found; supply --ffmpeg")
    if not 18 <= args.font_size <= 42 or not 1 <= args.fps <= 60:
        parser.error("font-size must be 18..42 and fps must be 1..60")
    if args.max_gap < 0 or args.min_hold <= 0 or args.end_hold <= 0 or args.lines_per_step <= 0:
        parser.error("timing must be positive (max-gap may be zero), and lines-per-step must be positive")
    if args.output.suffix.lower() != ".mp4":
        parser.error("output must have .mp4 extension")
    events = read_events(args.events)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    font_path = find_font(args.font)
    font = ImageFont.truetype(font_path, args.font_size)
    heading = ImageFont.truetype(find_font(args.font, bold=True), 31)
    small = ImageFont.truetype(font_path, 21)
    char_width = font.getlength("M")
    margin, top = 45, 175
    line_height = math.ceil(args.font_size * 1.34)
    rows = (HEIGHT - top - 100) // line_height
    if args.lines_per_step > rows:
        parser.error(f"lines-per-step must be <= {rows}, to keep every line visible")
    timestamp_width = max(len(stamp(event.t)) for event in events) + 2
    columns = math.floor((WIDTH - 2 * margin) / char_width) - timestamp_width
    buffer: deque[tuple[str, str]] = deque(maxlen=rows)
    segments = []
    current_milestone = ""
    replay_time = 0.0
    shortened = any(args.max_gap and events[i].t - events[i-1].t > args.max_gap for i in range(1, len(events)))
    label = "console replay | " + ("idle pauses shortened" if shortened else "recorded console events") + " | text paced for readability"
    total_lines = 0

    with tempfile.TemporaryDirectory(prefix="acram-console-") as temporary:
        directory = Path(temporary)
        for index, event in enumerate(events):
            if event.milestone:
                current_milestone = " ".join(event.milestone.splitlines())
            event_rows = []
            for line in event.text.rstrip("\n").split("\n"):
                wrapped = textwrap.wrap(line, width=columns, expand_tabs=False, replace_whitespace=False, drop_whitespace=False) or [""]
                color = line_color(line)
                for part_index, part in enumerate(wrapped):
                    prefix = stamp(event.t).ljust(timestamp_width) if part_index == 0 else " " * timestamp_width
                    event_rows.append((prefix + part, color))
            total_lines += len(event_rows)
            for offset in range(0, len(event_rows), args.lines_per_step):
                new_rows = event_rows[offset:offset + args.lines_per_step]
                buffer.extend(new_rows)
                final_step = offset + args.lines_per_step >= len(event_rows)
                gap = events[index + 1].t - event.t if final_step and index + 1 < len(events) else 0.0
                duration = max(args.min_hold, min(gap, args.max_gap) if args.max_gap else gap)
                if final_step and index + 1 == len(events):
                    duration = max(duration, args.end_hold)
                duration = math.ceil(duration * args.fps) / args.fps
                frame = Image.new("RGB", (WIDTH, HEIGHT), BG)
                draw = ImageDraw.Draw(frame)
                draw.rectangle((0, 0, WIDTH, 144), fill=PANEL)
                draw.text((margin, 22), args.title, font=heading, fill=TEXT)
                draw.text((margin, 68), label, font=small, fill=MUTED)
                if current_milestone:
                    milestone_rows = textwrap.wrap(current_milestone, width=130)
                    if len(milestone_rows) > 1:
                        raise ValueError("A milestone is too long for the header; keep it under 130 characters")
                    draw.text((margin, 105), current_milestone, font=small, fill=CYAN)
                for row_index, (line, color) in enumerate(buffer):
                    draw.text((margin, top + row_index * line_height), line, font=font, fill=color)
                footer_y = HEIGHT - 63
                draw.line((margin, footer_y - 20, WIDTH - margin, footer_y - 20), fill="#26384e", width=2)
                footer = f"CAPTURE {stamp(event.t)}     REPLAY {stamp(replay_time)}     EVENT {index + 1}/{len(events)}"
                draw.text((margin, footer_y), footer, font=small, fill=MUTED)
                snapshot = directory / f"frame-{len(segments):06}.png"
                frame.save(snapshot)
                segments.append({"image": snapshot.name, "duration": duration, "replayStart": round(replay_time, 6), "eventIndex": index, "captureTime": event.t, "wrappedLinesAdded": len(new_rows)})
                replay_time += duration
            if (index + 1) % 50 == 0:
                print(f"Rendered {index + 1}/{len(events)} recorded console events", flush=True)
        concat = directory / "timeline.ffconcat"
        lines = ["ffconcat version 1.0"]
        for segment in segments:
            lines.extend([f"file '{segment['image']}'", f"duration {segment['duration']:.8f}"])
        lines.append(f"file '{segments[-1]['image']}'")
        concat.write_text("\n".join(lines) + "\n", encoding="utf-8")
        # A relative concat input avoids old Windows FFmpeg treating drive letters
        # as URL schemes while resolving each relative PNG filename.
        command = [args.ffmpeg, "-hide_banner", "-loglevel", "warning", "-y", "-f", "concat", "-safe", "0", "-i", concat.name, "-vf", f"fps={args.fps}", "-t", f"{replay_time:.8f}", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", str(args.output.resolve())]
        print(f"Encoding {replay_time:.1f}s at {WIDTH}x{HEIGHT} from {len(events)} recorded events", flush=True)
        subprocess.run(command, check=True, cwd=directory)
        # Save an actual video frame for quick visual inspection; it is not a substitute for the video.
        shutil.copyfile(directory / segments[-1]["image"], args.output.with_suffix(".preview.png"))
    transcript = "\n".join(f"[{stamp(event.t)}] {event.text.rstrip()}" for event in events)
    args.output.with_suffix(".transcript.txt").write_text(transcript + "\n", encoding="utf-8")
    metadata = {
        "createdAtUtc": datetime.now(timezone.utc).isoformat(),
        "source": str(args.events.resolve()),
        "sourceSha256": hashlib.sha256(args.events.read_bytes()).hexdigest(),
        "output": str(args.output.resolve()),
        "videoSha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
        "format": "1920x1080 H.264 MP4; no audio",
        "rendering": "Replay of supplied console events; lines wrapped and scrolled in input order",
        "label": label,
        "idlePausesShortened": bool(shortened),
        "maximumIdleGapSeconds": args.max_gap,
        "minimumStepSeconds": args.min_hold,
        "events": len(events),
        "wrappedLines": total_lines,
        "captureEndSeconds": events[-1].t,
        "replayDurationSeconds": round(replay_time, 6),
        "fps": args.fps,
        "font": font_path,
        "fontSize": args.font_size,
        "segments": [{key: value for key, value in segment.items() if key != "image"} for segment in segments],
    }
    args.output.with_suffix(".replay.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {args.output.resolve()}", flush=True)


if __name__ == "__main__":
    main()
