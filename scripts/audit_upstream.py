"""Reproducible lexical comparison, not a copyright/authorship classifier."""
import argparse
import difflib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

TOKEN = re.compile(r"/\*.*?\*/|//[^\n]*|r?(?:\"\"\".*?\"\"\"|'''.*?'''|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')|[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|[^\s]", re.S)
def tokens(source):
    return [m.group() for m in TOKEN.finditer(source)
            if not m.group().startswith(("//", "/*"))]
def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])
def files(root, revision, scope):
    paths = git(root, "ls-tree", "-r", "--name-only", revision).decode().splitlines()
    paths = [p for p in paths if (p.startswith("lib/") and p.endswith(".dart")) or
             (scope in ("runtime", "app_runtime") and p.startswith("android/app/src/main/") and p.endswith((".kt", ".java")))]
    if scope in ("app", "app_runtime"):
        paths = [p for p in paths if not p.startswith("lib/generated/")]
    return {p: git(root, "show", revision+":"+p).decode("utf-8-sig") for p in paths}
def compare(local, upstream, size=20):
    upstream_tokens = {p: tokens(s) for p,s in upstream.items()}
    shingles = {tuple(t[i:i+size]) for t in upstream_tokens.values() for i in range(len(t)-size+1)}
    rows = []
    for path, source in local.items():
        t = tokens(source)
        u = upstream_tokens.get(path)
        mask = bytearray(len(t))
        for i in range(len(t)-size+1):
            if tuple(t[i:i+size]) in shingles:
                mask[i:i+size] = b"\1" * size
        state = "absent_path" if u is None else ("identical" if source == upstream[path] else
                 ("tokens_identical" if t == u else "modified"))
        aligned = 0 if u is None else sum(b.size for b in difflib.SequenceMatcher(None,u,t,autojunk=False).get_matching_blocks())
        rows.append({"path":path, "state":state, "nonempty_lines":sum(bool(s.strip()) for s in source.splitlines()),
                     "tokens":len(t), "same_path_aligned_tokens":aligned, "global_20_token_overlap":sum(mask)})
    counts = Counter(r["state"] for r in rows)
    sums = {k:sum(r[k] for r in rows) for k in ["nonempty_lines","tokens","same_path_aligned_tokens","global_20_token_overlap"]}
    return {"files":len(rows), "upstream_files":len(upstream), "upstream_tokens":sum(map(len,upstream_tokens.values())), "states":dict(counts), **sums,
            "same_path_aligned_percent":round(100*sums["same_path_aligned_tokens"]/sums["tokens"],2),
            "global_20_token_overlap_percent":round(100*sums["global_20_token_overlap"]/sums["tokens"],2),
            "per_file":rows}
def reachability(root, sources):
    edges={}
    for path, source in sources.items():
        refs=[]
        for statement in re.findall(r"^\s*(?:import|export)\s+[\"'].*?;", source, re.S | re.M):
            for uri in re.findall(r"[\"']([^\"']+)[\"']", statement):
                if not uri.endswith(".dart"):
                    continue
                if uri.startswith("package:xournalpp/"):
                    target="lib/"+uri.removeprefix("package:xournalpp/")
                elif ":" not in uri:
                    target=(root/path).parent.joinpath(uri).resolve().relative_to(root).as_posix()
                else:
                    continue
                if target in sources:
                    refs.append(target)
        edges[path]=refs
    visited=set()
    pending=["lib/main.dart", "lib/main_desktop.dart"]
    while pending:
        path=pending.pop()
        if path in visited:
            continue
        visited.add(path)
        pending.extend(edges.get(path, []))
    return {"entrypoints":["lib/main.dart", "lib/main_desktop.dart"],
            "unreachable_import_paths":sorted(set(sources)-visited),
            "method":"Static import/export graph including conditional branches; not symbol reachability"}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("upstream",type=Path)
    parser.add_argument("--output",type=Path,default=Path("docs/validation/upstream-audit.json"))
    parser.add_argument("--local-revision", default="HEAD")
    parser.add_argument("--upstream-revision", default="HEAD")
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    assert tokens("int a=1; // note\n") == tokens("int a = 1; /* note */")
    assert tokens("'//text'")[0] == "'//text'"
    revision=git(root,"rev-parse",args.local_revision).decode().strip()
    original=git(root,"rev-list","--max-parents=0",revision).decode().strip()
    upstream_revision=git(args.upstream,"rev-parse",args.upstream_revision).decode().strip()
    result={"local_revision":revision,"local_initial_revision":original,"upstream_revision":upstream_revision,
            "upstream_url":"https://gitlab.com/TheOneWithTheBraid/xournalpp_mobile", "shingle_size":20}
    for scope in ["lib","runtime","app","app_runtime"]:
        result[scope]=compare(files(root,revision,scope),files(args.upstream,upstream_revision,scope))
    result["initial_lib"]=compare(files(root,original,"lib"),files(args.upstream,upstream_revision,"lib"))
    result["reachability"] = reachability(root, files(root, revision, "lib"))
    args.output.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:({a:b for a,b in v.items() if a != "per_file"} if isinstance(v,dict) else v)
                      for k,v in result.items()},indent=2))
if __name__ == "__main__": main()
