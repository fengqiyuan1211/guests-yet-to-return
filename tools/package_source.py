"""Build a source submission from the current Git working tree, without local state."""
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    listed = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
    )
    candidates = sorted(set(name for name in listed.split(b"\0") if name))
    ignored_result = subprocess.run(
        ["git", "check-ignore", "--no-index", "-z", "--stdin"],
        cwd=ROOT, input=b"\0".join(candidates) + b"\0", capture_output=True,
    )
    if ignored_result.returncode not in (0, 1):
        raise RuntimeError("Could not check submission ignore rules")
    ignored = set(ignored_result.stdout.split(b"\0"))
    output = ROOT / "exports" / "guests-yet-to-return-source.zip"
    output.parent.mkdir(exist_ok=True)
    count = 0
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for raw in candidates:
            name = raw.decode("utf-8")
            path = ROOT / name
            if raw in ignored or not path.is_file() or path.is_symlink():
                continue
            archive.write(path, "guests-yet-to-return/" + name)
            count += 1
    print(f"{output}\n{count} files; {output.stat().st_size / 1024**2:.1f} MiB")


if __name__ == "__main__":
    main()
