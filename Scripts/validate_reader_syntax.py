"""Syntax-only audit. Does not typecheck Swift, execute tests, or verify native behavior.
Install tree-sitter==0.26.0 and tree-sitter-swift==0.7.4 into a temporary Python target.
Run with PYTHONPATH pointing to that target: python Scripts/validate_reader_syntax.py
"""
from pathlib import Path
from tree_sitter import Language, Parser
import tree_sitter_swift

root = Path(__file__).resolve().parent.parent
parser = Parser(Language(tree_sitter_swift.language()))
files = sorted((root / "Ahoge/Features/Reader").glob("*.swift"))
files += [root / "Ahoge/Domain/Preferences/ReaderParityPreferences.swift", root / "Scripts/ReaderPreferencesRegression.swift", root / "Scripts/ReaderRenderRegression.swift"]
errors = []
for file in files:
    tree = parser.parse(file.read_bytes())
    pending = [tree.root_node]
    while pending:
        node = pending.pop()
        if node.type == "ERROR" or node.is_missing:
            errors.append(f"{file.relative_to(root)}:{node.start_point[0] + 1}: {node.type}")
        pending.extend(node.children)
for error in errors:
    print(error)
print(f"Reader Swift syntax parse: {len(files)} files; {len(errors)} errors. No typecheck or native runtime claim.")
raise SystemExit(bool(errors))
