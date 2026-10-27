#!/usr/bin/env python3
"""Works out the next release from the commits since the last one, and writes its notes.

Commit messages follow Conventional Commits (https://www.conventionalcommits.org):

    feat(seasons): a page for each season          -> a minor release: 1.2.0 -> 1.3.0
    fix(cast): full quality on newer servers       -> a patch release: 1.2.0 -> 1.2.1
    perf: ...                                      -> a patch release
    feat!: ...  or a "BREAKING CHANGE:" line       -> a major release: 1.2.0 -> 2.0.0
    docs: / chore: / ci: / test: / refactor: / style: / build:  -> nothing to release

For an app, "breaking" means: support dropped for an OS or Jellyfin version, saved settings or
downloads that don't carry over, or a redesign meant as a new major version.

The build number is the last release's plus one (the stores need it to always go up).

The notes are made from the feat and fix summaries, so write those for the people using the app.
Google Play's "What's new" is the same lines, cut to fit its 500 characters.

    next_release.py [--dry-run] [--notes PATH]

Prints version=, build=, release= lines (for $GITHUB_OUTPUT); with --notes, writes the notes there.
"""

import argparse
import re
import subprocess
import sys

TYPE = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<summary>.+)$")
RELEASING = {"feat": "minor", "fix": "patch", "perf": "patch"}
PLAY_LIMIT = 500


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def last_release() -> tuple[str | None, int]:
    """The latest v* tag and the build number at it (0 and None if there's none yet)."""
    tags = git("tag", "--list", "v*", "--sort=-v:refname").split()
    if not tags:
        return None, 0
    tag = tags[0]
    pubspec = git("show", f"{tag}:pubspec.yaml")
    version = re.search(r"^version:\s*(\S+)", pubspec, re.M).group(1)
    return tag, int(version.split("+")[1]) if "+" in version else 0


def commits_since(tag: str | None) -> list[tuple[str, str]]:
    """(subject, body) of each commit since [tag], oldest first."""
    log = git("log", "--reverse", "--format=%s%x1f%b%x1e", f"{tag}..HEAD" if tag else "HEAD")
    return [tuple(entry.strip("\n").split("\x1f", 1)) for entry in log.split("\x1e") if entry.strip()]


def classify(commits: list[tuple[str, str]]) -> tuple[str | None, dict[str, list[str]]]:
    """The bump (major, minor, patch or None) and the summaries by section."""
    bump = None
    order = [None, "patch", "minor", "major"]
    sections: dict[str, list[str]] = {"breaking": [], "feat": [], "fix": []}
    for subject, body in commits:
        match = TYPE.match(subject)
        if not match:
            continue
        kind = match["type"]
        breaking = bool(match["bang"]) or re.search(r"^BREAKING[ -]CHANGE:", body, re.M) is not None
        level = "major" if breaking else RELEASING.get(kind)
        if level and order.index(level) > order.index(bump):
            bump = level
        summary = match["summary"].strip()
        summary = summary[0].upper() + summary[1:]
        if breaking:
            sections["breaking"].append(summary)
        if kind == "feat":
            sections["feat"].append(summary)
        elif kind in ("fix", "perf"):
            sections["fix"].append(summary)
    return bump, sections


def bumped(version: str, bump: str) -> str:
    major, minor, patch = (int(n) for n in version.split("."))
    if bump == "major":
        return f"{major + 1}.0.0"
    if bump == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def play_text(sections: dict[str, list[str]]) -> str:
    """The features then the fixes, one per line, as many whole lines as fit in 500 characters."""
    lines, used = [], 0
    for line in sections["feat"] + sections["fix"]:
        if line in lines:
            continue
        extra = len(line) + (1 if lines else 0)
        if used + extra > PLAY_LIMIT:
            break
        lines.append(line)
        used += extra
    return "\n".join(lines) or "Fixes and improvements."


def notes(version: str, build: int, sections: dict[str, list[str]]) -> str:
    out = [f"# Chameleon {version} (build {build})", "", '## Google Play "What\'s new" (en-US, under 500 characters)', ""]
    out += ["```", play_text(sections), "```", "", "## Full changes", ""]
    for key, title in (("breaking", "Breaking changes"), ("feat", "New"), ("fix", "Fixed")):
        if sections[key]:
            out += [f"**{title}**"] + [f"- {line}" for line in sections[key]] + [""]
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="a version to build even with nothing to release")
    parser.add_argument("--notes", help="where to write the release notes")
    args = parser.parse_args()

    tag, build = last_release()
    bump, sections = classify(commits_since(tag))
    release = bump is not None
    version = bumped(tag[1:] if tag else "0.0.0", bump or "patch")
    build += 1

    if args.notes:
        with open(args.notes, "w") as f:
            f.write(notes(version, build, sections))
    print(f"version={version}")
    print(f"build={build}")
    print(f"release={'true' if release or args.dry_run else 'false'}")
    summary = f"{tag or 'nothing'} -> {version} (build {build}): {bump or 'nothing to release'}"
    print(summary, file=sys.stderr)


if __name__ == "__main__":
    main()
