"""Package only the verified recording, sanitized evidence, and repeatable tools."""
import hashlib
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
files = [root / 'README.md']
files += sorted(root.glob('UC1-SBOM-UAM-console.*'))
files += sorted(root.glob('UC1-initial-SBOM-UAM-console.*'))
files += [p for p in sorted((root / 'recording').glob('*')) if p.suffix in {'.json', '.jsonl', '.txt'}]
files += [p for p in sorted((root / 'recording-latest').glob('*')) if p.suffix in {'.json', '.jsonl', '.txt', '.log', '.csv'}]
files += [root / name for name in ('initial-adi-transactions.json', 'latest-live-summary.json') if (root / name).is_file()]
files += [p for p in sorted((root / 'tools').glob('*')) if p.suffix in {'.py', '.m', '.md', '.sh'}]
manifest = root / 'SHA256SUMS.txt'
manifest.write_bytes(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root).as_posix()}\n' for p in files).encode('utf-8'))
archive = root / 'UC1-SBOM-UAM-recording.zip'
temporary = archive.with_suffix('.zip.tmp')
# Sanitized tar members may have epoch file times; capture timestamps remain
# unchanged inside their JSON/text. ZIP metadata cannot represent pre-1980.
with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, strict_timestamps=False) as out:
    for path in files + [manifest]:
        out.write(path, path.relative_to(root).as_posix())
temporary.replace(archive)
print(f'Packaged {len(files)+1} files: {archive}')
