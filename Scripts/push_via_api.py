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

只依赖标准库（urllib），不需要 requests。
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
WORKFLOW = ".github/workflows/build-unsigned-ipa.yml"


def make_opener() -> urllib.request.OpenerDirector:
    # 显式不使用环境代理，避免代理把 api.github.com 打挂
    return urllib.request.build_opener(urllib.request.ProxyHandler({}))


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

    opener = make_opener()

    def call(method: str, path: str, payload: dict | None = None, allow_404: bool = False):
        data = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(
            API + path,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "kitesim-push",
                "Content-Type": "application/json",
            },
        )
        try:
            with opener.open(req, timeout=90) as resp:
                body = resp.read()
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as exc:
            if allow_404 and exc.code == 404:
                return None
            raise SystemExit(f"{method} {path} -> {exc.code}: {exc.read()[:400].decode(errors='replace')}")

    root, owner, repo, branch = args.root, args.owner, args.repo, args.branch
    files = subprocess.run(
        ["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True
    ).stdout.split()
    if not files:
        print("没有可提交的文件", file=sys.stderr)
        return 1

    # 1) 确保远端已有初始提交
    probe = call("GET", f"/repos/{owner}/{repo}/git/ref/heads/{branch}", allow_404=True)
    if probe is None:
        print("远端仓库为空，先创建初始提交…")
        path = os.path.join(root, WORKFLOW)
        if not os.path.exists(path):
            print(f"空仓库需要先有 {WORKFLOW}", file=sys.stderr)
            return 1
        with open(path, encoding="utf-8") as fh:
            body = fh.read()
        head_part, sep, tail = body.partition("permissions:")
        head_part = head_part.replace("  push:\n    branches: [main]\n", "")
        call("PUT", f"/repos/{owner}/{repo}/contents/{WORKFLOW}", {
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
        sha = call("POST", f"/repos/{owner}/{repo}/git/blobs", {
            "content": base64.b64encode(data).decode(),
            "encoding": "base64",
        })["sha"]
        tree.append({"path": rel, "mode": "100644", "type": "blob", "sha": sha})
        print(f"  [{i}/{len(files)}] {rel} ({len(data)}B)")

    t = call("POST", f"/repos/{owner}/{repo}/git/trees", {"base_tree": base_tree, "tree": tree})

    # 3) 提交并移动分支
    c = call("POST", f"/repos/{owner}/{repo}/git/commits", {
        "message": args.message, "tree": t["sha"], "parents": [head],
    })
    call("PATCH", f"/repos/{owner}/{repo}/git/refs/heads/{branch}", {"sha": c["sha"], "force": False})
    print("PUSH OK", c["sha"][:7], c["html_url"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
