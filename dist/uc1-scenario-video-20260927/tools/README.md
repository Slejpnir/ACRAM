# Console video renderer

This renderer creates a **clearly labelled replay of real console output**. It does not run the scenario, synthesize terminal output, infer success, or contact ADI. The caller must first capture the real scenario and provide its console events.

Requirements found on this workstation:

- Python: `C:\Python314\python.exe`
- Pillow 12.1.0 (already installed for that Python)
- FFmpeg with `libx264`: `C:\Program Files\ImageMagick-7.0.9-Q16\ffmpeg.exe`
- Consolas: `C:\Windows\Fonts\consola.ttf` (or a monospace font supplied with `--font`)

Run from PowerShell, supplying the actual capture file:

```powershell
& 'C:\Python314\python.exe' '.\tools\render_console_video.py' '.\console-events.jsonl' '.\UC1-SBOM-UAM-console.mp4' --ffmpeg 'C:\Program Files\ImageMagick-7.0.9-Q16\ffmpeg.exe'
```

Each UTF-8 JSONL line must be an object with `t` (nonnegative seconds from capture start, in nondecreasing order) and `text` (an actual captured console string, which can contain newlines). The optional `milestone` string is displayed in the header until the next supplied milestone. Only use milestones grounded in the captured run. Do not put secrets in the capture file.

The output is a readable 1920 × 1080 H.264 MP4 with no audio. Lines wrap and scroll in input order. Original capture timestamps stay visible; the footer distinguishes capture time from replay time. By default, idle gaps are capped at two seconds and each group of up to three wrapped lines receives at least 0.55 seconds of screen time. The video labels this timing treatment explicitly. Use `--max-gap 0` to preserve long pauses; readability pacing still applies. A final five-second hold makes the last output readable.

Useful options: `--title`, `--font-size` (default 26), `--max-gap`, `--min-hold`, `--lines-per-step`, `--end-hold`, `--fps` (default 12). Every wrapped line is displayed; `--lines-per-step` cannot exceed the available screen rows.

The renderer also saves a `.transcript.txt` with all supplied console text, `.preview.png` containing the final frame, and `.replay.json` with source/video SHA-256 hashes and the exact timing map. Temporary frame files are removed after encoding. Existing files with the selected output names are replaced.
