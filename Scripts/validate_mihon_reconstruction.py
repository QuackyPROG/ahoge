"""Available source/fixture audits only; never Swift compilation or native proof."""
from pathlib import Path
import argparse, collections, hashlib, json, re, subprocess, sys
root = Path(__file__).resolve().parents[1]
args = argparse.ArgumentParser()
args.add_argument("--parser-path", type=Path, required=True)
config = args.parse_args()
sys.path.insert(0, str(config.parser_path))
from tree_sitter import Language, Parser
import tree_sitter_swift
parser = Parser(Language(tree_sitter_swift.language()))

def diagnostics(data):
    result = []
    pending = [parser.parse(data).root_node]
    while pending:
        node = pending.pop()
        if node.type == "ERROR" or node.is_missing:
            result.append((node.start_point[0] + 1, node.type, data[node.start_byte:node.end_byte].decode("utf8", errors="replace")))
        pending.extend(node.children)
    return sorted(result)

files = sorted((root / "Ahoge").rglob("*.swift")) + sorted((root / "Scripts").glob("*.swift"))
failures, inherited = [], []
for file in files:
    relative = file.relative_to(root).as_posix()
    data = file.read_bytes()
    if b"\xef\xbf\xbd" in data:
        failures.append(f"{relative}: Unicode replacement character")
    errors = diagnostics(data)
    if errors:
        baseline = subprocess.run(["git", "show", "HEAD:" + relative], cwd=root, capture_output=True)
        if baseline.returncode == 0 and errors == diagnostics(baseline.stdout):
            inherited.append((relative, errors))
        else:
            failures.append(f"{relative}: {errors}")

# Top-level interface names are owned once. Nested types and extensions do not
# assert runtime correctness; this catches accidental duplicate destination definitions.
view_names = collections.defaultdict(list)
for file in (root / "Ahoge/Features").rglob("*.swift"):
    for name in re.findall(r"^struct\s+(\w+)\s*:\s*(?:View\b|UIViewControllerRepresentable\b)", file.read_text(encoding="utf8"), re.M):
        view_names[name].append(str(file.relative_to(root)))
for name, locations in view_names.items():
    if len(locations) > 1:
        failures.append(f"Duplicate view {name}: {locations}")

# Source-bound interface and ownership assertions complement the syntax parser.
required = {
 "Ahoge/App/AppModel+CollectionState.swift": ["func chapterState(", "func setChaptersRead(", "func assignCategories(", "lockLibraryEdits", "func refreshLibrary("],
 "Ahoge/App/AppModel+Packages.swift": ["PackageVersion.newer", "trustConsent", "hasRuntime", "https", "admittedRecords", "PackageAdmission.records"],
 "Ahoge/Data/RuntimeSourceRepository.swift": ["page: Int = 1", "runtime.popularManga(page: page)", "SourceSearchRequest(query: query, page: page"],
 "Ahoge/Features/Browse/GlobalSearchView.swift": ["0..<4", "group.cancelAll()", "retryTasks.values.forEach", "searchGeneration.accepts(token)", "model.searchSource"],
 "Ahoge/Domain/Persistence/AhogeBackup.swift": ["BackupJSONValidation.validate(data)", "owners[$0.chapterID]", "Self.maximumBytes", "sections.contains(.library)"],
 "Ahoge/Domain/Persistence/BackupRestorePlan.swift": ["validateReferences(next)", "current.knownChapters", "backup.collection == nil ? existing : incoming", "state.history.allSatisfy"],
 "Ahoge/Domain/Source/SourceFeedSession.swift": ["let descriptor: SourceFeedDescriptor", "request.generation == generation", "page: page + 1", "page = 0", "descriptor.allowsPagination", "!request.descriptor.allowsPagination"],
 "Ahoge/Domain/Source/SourceFeedPolicy.swift": ["enum SourceFeedOperation", "enum NatsuSearchQuery", "NatsuSearchQuery.deepLinkSlug", "supported.allowsPagination", "supported.applying(filters)", 'case "mangadex"', 'case "heancms"', 'default: return .unavailable'],
 "Ahoge/App/AppModel+Discovery.swift": ["switch SourceFeedOperation.make", "query: request.query, page: request.page, filters: request.filters"],
 "Ahoge/Features/Browse/BrowseView.swift": ["feedSession.nextRequest()", "feedSession.accepts(request)", "onChange(of: selectedRuntimeFilters)", "filters: descriptor.filters", "let request = beginReload()", "feedKind == .search && searchFilters.isAvailable", "if supported.types", "if supported.ascending", "Search with filters", "guard feedKind == .search else { return [] }"],
 "Ahoge/Data/Sources/NatsuIdSourceEngine.swift": ["NatsuSearchQuery.deepLinkSlug(from: request.query", "NatsuSearchQuery.deepLinkSlug(from: mangaIDOrURL"],
 "Ahoge/Data/SourceRepoImporter.swift": ["RepositoryRefreshPolicy.refresh(record)"],
 "Ahoge/Domain/Source/SourceDomain.swift": ["return record.retainingCatalog(after: error)"],
 "Ahoge/App/AppModel+Backup.swift": ["BackupRestorePlan.apply(backup, to: base)", "next.knownChapters","try commitState(next", "portableRepositories", "supportingMangas", "lockLibraryEdits"],
 "Ahoge/Domain/Persistence/MigrationStateTransfer.swift": ["lockLibraryEdits", "originalEntry.categoryIDs", "existing?.pageIndex", "options.removeOriginal", "old.updatedAt"],
 "Ahoge/App/DownloadQueueCoordinator.swift": ["guard activeJobID == jobID", "Retain transport ownership"],
 "Ahoge/App/DownloadsService.swift": ["try Task.checkCancellation()", "allowsCellularAccess = !wifiOnly", "defer { if !didCommit"],
 "Scripts/MihonDomainRegression.swift": ["Legacy single membership", "Read and update-seen", "Duplicate target identities", "Migration edit lock", "Duplicate object keys", "Write failure must throw", "No overlapping replacement transport", "Cancelled/changed query", "Cold launch resolves", "History-only restore merges", "Refresh failures preserve", "Filter change during request", "Request spy observes", "Search dispatch forwards supported filters", "MangaDex dispatch drops unsupported kinds", "Popular/Latest dispatch cannot claim search filters", "Successful nonempty direct lookup has no Load more", "Nonmatching host/path and ID", "Failed direct lookup cannot retry a later page", "Other adapters do not misclassify URLs"],
 "Scripts/ReaderPreferencesRegression.swift": ["round", "invert", "default"],
 "Scripts/ReaderRenderRegression.swift": ["verticalPaged", "rotateClockwise", "sourcePageIndex"],
}
for name, needles in required.items():
    text = (root / name).read_text(encoding="utf8")
    for needle in needles:
        if needle.lower() not in text.lower():
            failures.append(f"Missing source-contract assertion {name}: {needle}")

# Required changed data seams are backed by real Swift harness cases. We only
# validate fixture JSON readability here; production Swift assertions remain unrun.
harness = (root / "Scripts/MihonDomainRegression.swift").read_text(encoding="utf8")
json_literals = re.findall(r'#"(.*?)"#', harness)
valid_literals = 0
for literal in json_literals:
    try:
        json.loads(literal)
        valid_literals += 1
    except json.JSONDecodeError:
        pass
assert valid_literals >= 5, "Missing readable compatibility/negative input fixtures"

changed = subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=root, text=True).splitlines()
protected = [path for path in changed if path.startswith((".yaaw-core/system/", ".codex/", ".github/", "Ahoge.xcodeproj/", "Distribution/", "Ahoge/Assets.xcassets/")) or path in ["Ahoge/App/BiometricAuthenticator.swift", "Ahoge/App/BackgroundTaskManager.swift", "Ahoge/App/AppModel+Security.swift", "Ahoge/Features/Shared/MangaCoverView.swift", "Ahoge/Features/More/NativeUpdateView.swift"]]
if protected:
    failures.append("Protected changed paths: " + ", ".join(protected))
for path, errors in inherited:
    print("UNCHANGED_BASELINE_PARSER_LIMITATION", path, errors)
for failure in failures:
    print("FAIL", failure)
print(f"Swift source syntax/interface/fixture audit: {len(files)} files, {valid_literals} readable inline JSON fixtures, {len(failures)} new failures.")
print("LIMITATION: syntax/source assertions do not typecheck or execute Swift. Mac domain, reader and native regressions remain DEFERRED_NATIVE_VALIDATION.")
raise SystemExit(bool(failures))
