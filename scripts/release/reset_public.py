#!/usr/bin/python3 -I
"""Rebuild a public history of ONE scrubbed commit per released version, locally.

  reset_public.py OUTDIR --wordlist FILE [--through vX.Y.Z] [--repo DIR]
      (or the PRIVATE_WORDLIST env var with the list's lines)

For every vX.Y.Z tag in the private repo up to --through (default: all), in
SemVer order, this builds the public copy of that tag exactly as
build_public.py does (git archive, private/ and the CURRENT
private/public-exclude.txt removed, the CURRENT private/history-fixups.txt
applied to old releases that predate the checks, pattern checks, the word list on content
and paths, link check) and commits it to a brand-new repository in OUTDIR as
"docker-pve X.Y.Z" by the bot identity, tagged vX.Y.Z, dated like the original
tagged commit. The first version is the root commit.

It never pushes and never touches the public repository. Any failed check
stops it and leaves nothing usable. Pushing the result over the public
repository's history is a separate, deliberate step (private/RELEASING.md).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_public  # noqa: E402
import publish_public  # noqa: E402


def git(repo, *args, env=None):
    return publish_public.git(repo, *args, env=env)


def version_tags(repo, through=None):
    tags = [t for t in git(repo, "tag", "--list", "v*").split() if re.fullmatch(r"v\d+\.\d+\.\d+", t)]
    tags.sort(key=publish_public.vkey)
    if through:
        if through not in tags:
            raise build_public.PublishError("%s is not a tag of the private repo" % through)
        tags = [t for t in tags if publish_public.vkey(t) <= publish_public.vkey(through)]
    if not tags:
        raise build_public.PublishError("no vX.Y.Z tags to rebuild")
    return tags


def reset(out, patterns, repo=".", through=None):
    if os.path.exists(out) and os.listdir(out):
        raise build_public.PublishError("output directory %s is not empty" % out)
    tags = version_tags(repo, through)
    tmp = tempfile.mkdtemp()
    excl_file = os.path.join(tmp, "excl.txt")
    with open(excl_file, "w", encoding="utf-8") as f:
        f.write(git(repo, "show", "HEAD:private/public-exclude.txt"))
    excludes = build_public.read_excludes(excl_file)
    fixups = []
    fix_file = os.path.join(tmp, "fixups.txt")
    try:
        with open(fix_file, "w", encoding="utf-8", newline="") as f:
            f.write(git(repo, "show", "HEAD:private/history-fixups.txt"))
        fixups = build_public.read_fixups(fix_file)
    except publish_public.PublishError:
        pass                                   # no fixups file: old tags are taken as they are
    os.makedirs(out, exist_ok=True)
    git(out, "init", "-q", "-b", "main")
    for tag in tags:
        version = tag[1:]
        msg = "%s %s" % (publish_public.NAME, version)
        copy = os.path.join(tmp, "copy-" + version)
        try:
            build_public.build(tag, copy, patterns, [msg], repo, excludes, fixups)
        except build_public.PublishError as e:
            raise build_public.PublishError("%s: %s" % (tag, e))
        when = git(repo, "log", "-1", "--format=%aI", tag + "^{commit}")
        env = dict(publish_public.BOT, GIT_AUTHOR_DATE=when, GIT_COMMITTER_DATE=when)
        publish_public.replace_tree(out, copy)
        git(out, "commit", "-q", "--allow-empty", "-m", msg, env=env)
        git(out, "tag", "-a", tag, "-m", msg, env=env)
        shutil.rmtree(copy)
    shutil.rmtree(tmp)
    return tags


def main(argv):
    try:
        out = argv[1]
        wl = argv[argv.index("--wordlist") + 1] if "--wordlist" in argv else None
        through = argv[argv.index("--through") + 1] if "--through" in argv else None
        repo = argv[argv.index("--repo") + 1] if "--repo" in argv else "."
        patterns = build_public.load_wordlist(wl, os.environ.get("PRIVATE_WORDLIST"))
        tags = reset(out, patterns, repo, through)
    except (build_public.PublishError, publish_public.PublishError, IndexError,
            subprocess.CalledProcessError) as e:
        print("reset_public: STOPPED, nothing is published.\n%s" % e, file=sys.stderr)
        return 1
    print("reset_public: OK, %d commits (%s) in %s; nothing pushed" % (len(tags), ", ".join(tags), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
