#!/usr/bin/env python3
"""Add/update the standard header on every *.sv file under the given directory."""

import argparse
import datetime
import os
import re

COMPANY = "SILICIOM TECHNOLOGIES PVT LTD"

# File types whose contents are rewritten when fixing references.
TEXT_EXTS = {".sv", ".v", ".vh", ".do", ".tcl", ".f", ".cfg", ".list"}

HEADER_TPL = """//=========================================================================================
// File         : {filename}
// Project      : {project}
// Description  : {description}
// Author       : {author}
// Date         : {date}
//=========================================================================================

/**********************************************************************************************************************
* Copyright by the {company},
* By using, accessing or downloading any part of this file/document,  including by copying, saving,
* distributing, displaying or preparing derivatives of,
* you agree to be and are bound to the terms of the {company} license agreement.
* All other rights reserved.
***********************************************************************************************************************/

"""

# Matches the header block from the top of the file (leading blank lines and whitespace allowed).
HEADER_RE = re.compile(
    r"^[ \t]*\n*(?:\s*//==+[^\n]*\n.*?//==+[^\n]*\n)?"
    r"[ \t]*\n*(?:\s*/\*[\s\S]*?\*/\n?)*"
    r"[ \t]*\n*",
    re.DOTALL,
)


def build_header(path, root, project, description, author):
    rel = os.path.relpath(path, root)
    return HEADER_TPL.format(
        filename=os.path.basename(path),
        project=project,
        description=description or rel,
        author=author or "",
        date=datetime.date.today().isoformat(),
        company=COMPANY,
    )


def update_file(path, root, project, description, author):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    header = build_header(path, root, project, description, author)
    new_content, n = HEADER_RE.subn(lambda m: header, content, count=1)

    if n == 0:
        new_content = header + content

    if new_content != content:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(new_content)
        return True
    return False


def fix_refs(root, dry_run=False):
    """Replace 'PCIE' with 'PCIe' inside text file contents (include paths, class names, ...)."""
    fixed = 0

    for dirpath, _dirnames, filenames in os.walk(root):
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            ext = os.path.splitext(name)[1].lower()
            if ext not in TEXT_EXTS:
                continue
            if path == os.path.abspath(__file__):
                continue
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()
            except OSError:
                continue
            if "PCIE" not in content:
                continue
            new_content = content.replace("PCIE", "PCIe")
            if dry_run:
                print("would fix refs :", os.path.relpath(path, root))
            else:
                with open(path, "w", encoding="utf-8", newline="") as f:
                    f.write(new_content)
            fixed += 1

    return fixed


def _target_blocked(old, new):
    """Return True only if an entry with the *exact* target name already exists.
    Case-variant entries (common on case-insensitive mounts) do not block a rename."""
    target_base = os.path.basename(new)
    try:
        stored = os.listdir(os.path.dirname(new))
    except OSError:
        return False
    return target_base in stored


def rename_entries(root, dry_run=False):
    """Rename files and directories replacing 'PCIE' with 'PCIe' in names."""
    renamed = 0

    dirs = []
    for dirpath, dirnames, _filenames in os.walk(root):
        for d in dirnames:
            dirs.append(os.path.join(dirpath, d))
    for old in sorted(dirs, key=lambda p: p.count(os.sep), reverse=True):
        base = os.path.basename(old)
        if "PCIE" not in base:
            continue
        new = os.path.join(os.path.dirname(old), base.replace("PCIE", "PCIe"))
        if _target_blocked(old, new):
            continue
        if dry_run:
            print("would rename dir :", old, "->", new)
        else:
            os.rename(old, new)
        renamed += 1

    for dirpath, _dirnames, filenames in os.walk(root):
        for name in sorted(filenames):
            if "PCIE" not in name:
                continue
            old = os.path.join(dirpath, name)
            new = os.path.join(dirpath, name.replace("PCIE", "PCIe"))
            if _target_blocked(old, new):
                continue
            if dry_run:
                print("would rename file:", old, "->", new)
            else:
                os.rename(old, new)
            renamed += 1

    return renamed


def main():
    parser = argparse.ArgumentParser(
        description="Add/update the standard header on every *.sv file."
    )
    parser.add_argument("root", nargs="?", default=".",
                        help="Root directory to scan (default: current dir)")
    parser.add_argument("--project", default="PCIE_Gen6", help="Project name in the header")
    parser.add_argument("--description", default="",
                        help="Description text (default: relative file path)")
    parser.add_argument("--author", default="", help="Author name in the header")
    parser.add_argument("--rename", action="store_true",
                        help="Rename files/dirs replacing 'PCIE' with 'PCIe' before updating headers")
    parser.add_argument("--no-fix-refs", action="store_true",
                        help="When renaming, do NOT rewrite 'PCIE' to 'PCIe' inside file contents")
    parser.add_argument("--dry-run", action="store_true",
                        help="Only print what would change without writing")
    args = parser.parse_args()

    root = os.path.abspath(args.root)

    if args.rename:
        renamed = rename_entries(root, args.dry_run)
        print(f"{renamed} file(s)/dir(s) {'to be ' if args.dry_run else ''}renamed.")
        if not args.no_fix_refs:
            fixed = fix_refs(root, args.dry_run)
            print(f"{fixed} file(s) {'to be ' if args.dry_run else ''}ref-fixed.")
    updated = 0
    unchanged = 0

    for dirpath, _dirnames, filenames in os.walk(root):
        for name in sorted(filenames):
            if not name.endswith(".sv"):
                continue
            path = os.path.join(dirpath, name)
            if args.dry_run:
                print("would update:", os.path.relpath(path, root))
                updated += 1
                continue
            if update_file(path, root, args.project, args.description, args.author):
                print("updated  :", os.path.relpath(path, root))
                updated += 1
            else:
                unchanged += 1

    print(f"\nDone. {updated} file(s) {'to be ' if args.dry_run else ''}updated, "
          f"{unchanged} already up-to-date.")


if __name__ == "__main__":
    main()
