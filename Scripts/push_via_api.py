#!/usr/bin/env python3
"""把本地工作区当前内容推送到 GitHub 仓库（单次提交，触发一次构建）。

为什么需要它：部分网络环境下 `github.com:443`（git 通道）不可达，但
`api.github.com` 正常。此脚本只走 REST API，等价于一次 `git push`。

用法：
    export GH_TOKEN=ghp_xxx          # 需要 repo + workflow 权限
    python3 Scripts/push_via_api.py
    python3 Scripts/push_via_api.py --owner me --repo kitesim-ios --message "fix: xxx"

说明：
- 读取 `git ls-files` 的结果，因此自动遵守 .gitignore；
- 以远端 `main` 的最新提交为父，构建一棵新树后移动 ref；
- 空仓库（无任何提交）无法直接建树，脚本会自动先用 Contents API 建一个
  仅含 workflow_dispatch 的流水线作为初始提交，再覆盖成完整内容，
  这样整个过程只触发一次构建。

依赖：pip install requests
"""
from __future__ import annotations

import argparse
import base64
import os
import subprocess
import sys

import requests

API = "https://api.github.com"
WORKFLOW = ".github/workflows/build-unsigned-ipa.yml"


def make_session(token: str) -> requests.Session:
    s = requests.Session()
    s.headers.update({
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "kitesim-push",
    })
    # 直连 api.github.com；不让环境里的代理变量干扰
    s.trust_env = False
    return s


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", default="Xieqiuyu823")
    ap.add_argument("--repo", default="kitesim-ios")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--message", default="chore: update from local workspace")
    ap.add_argument("--root", default=".", help="本地仓库根目录")
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN")
    if not token:
        print("缺少环境变量 GH_TOKEN", file=sys.stderr)
        return 2

    s = make_session(token)

    def call(method: str, path: str, **kw) -> dict:
        r = s.request(method, API + path, timeout=90, **kw)
        if r.status_code not in (200, 201, 204):
            raise SystemExit(f"{method} {path} -> {r.status_code}: {r.text[:400]}")
        return r.json() if r.content else {}

    root, owner, repo, branch = args.root, args.owner, args.repo, args.branch
    files = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True,
                           text=True, check=True).stdout.split()
    if not files:
        print("没有可提交的文件", file=sys.stderr)
        return 1

    # 1) 确保远端已有初始提交
    probe = s.get(f"{API}/repos/{owner}/{repo}/git/ref/heads/{branch}", timeout=60)
    if probe.status_code == 404:
        print("远端仓库为空，先创建初始提交…")
        path = os.path.join(root, WORKFLOW)
        if not os.path.exists(path):
            print(f"空仓库需要先有 {WORKFLOW}", file=sys.stderr)
            return 1
        with open(path, encoding="utf-8") as fh:
            body = fh.read()
        head_part, sep, tail = body.partition("permissions:")
        head_part = head_part.replace("  push:\n    branches: [main]\n", "")
        call("PUT", f"/repos/{owner}/{repo}/contents/{WORKFLOW}", json={
            "message": "chore: bootstrap (dispatch only)",
            "content": base64.b64encode((head_part + sep + tail).encode()).decode(),
        })

    head = call("GET", f"/repos/{owner}/{repo}/git/ref/heads/{branch}")["object"]["sha"]
    base_tree = call("GET", f"/repos/{owner}/{repo}/git/commits/{head}")["tree"]["sha"]

    # 2) 上传 blob 并建树
    tree = []
    for i, rel in enumerate(files, 1):
        with open(os.path.join(root, rel), "rb") as fh:
            data = fh.read()
        sha = call("POST", f"/repos/{owner}/{repo}/git/blobs", json={
            "content": base64.b64encode(data).decode(),
            "encoding": "base64",
        })["sha"]
        tree.append({"path": rel, "mode": "100644", "type": "blob", "sha": sha})
        print(f"  [{i}/{len(files)}] {rel} ({len(data)}B)")

    t = call("POST", f"/repos/{owner}/{repo}/git/trees",
             json={"base_tree": base_tree, "tree": tree})

    # 3) 提交并移动分支
    c = call("POST", f"/repos/{owner}/{repo}/git/commits",
             json={"message": args.message, "tree": t["sha"], "parents": [head]})
    call("PATCH", f"/repos/{owner}/{repo}/git/refs/heads/{branch}",
         json={"sha": c["sha"], "force": False})
    print("PUSH OK", c["sha"][:7], c["html_url"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
