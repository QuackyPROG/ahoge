"""Compile and execute the actual Foundation Swift domain seams when swiftc exists."""
from pathlib import Path
import shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
compiler = shutil.which("swiftc")
if not compiler:
    print("DEFERRED_NATIVE_VALIDATION: swiftc unavailable; actual Swift regression harness was not executed.")
    raise SystemExit(2)
files = list((root / "Ahoge/Domain").rglob("*.swift"))
files += [root / "Ahoge/App/DownloadQueueCoordinator.swift", root / "Ahoge/Data/AtomicSnapshotWriter.swift", root / "Scripts/MihonDomainRegression.swift"]
with tempfile.TemporaryDirectory(prefix="ahoge-domain-") as temp:
    executable = Path(temp) / "regressions"
    subprocess.run([compiler, "-parse-as-library", *map(str, files), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    reader = Path(temp) / "reader-preferences"
    subprocess.run([compiler, str(root / "Ahoge/Domain/Preferences/ReaderParityPreferences.swift"), str(root / "Scripts/ReaderPreferencesRegression.swift"), "-o", str(reader)], check=True)
    subprocess.run([str(reader)], check=True)
    render = Path(temp) / "reader-render"
    subprocess.run([compiler, "-parse-as-library", *map(str, (root / "Ahoge/Domain").rglob("*.swift")), str(root / "Ahoge/Features/Reader/ReaderRenderModels.swift"), str(root / "Ahoge/Features/Reader/ReaderViewModels.swift"), str(root / "Ahoge/Features/Reader/ReaderInteractionPolicy.swift"), str(root / "Ahoge/Features/Reader/ReaderProgressPolicy.swift"), str(root / "Scripts/ReaderRenderRegression.swift"), "-o", str(render)], check=True)
    subprocess.run([str(render)], check=True)
