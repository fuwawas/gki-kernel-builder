"""把 gki-kernel-builder 打包成可分发的 zip。"""
import os
import shutil
import zipfile
from datetime import datetime

SRC = os.path.dirname(os.path.abspath(__file__))
DIST = os.path.join(os.path.dirname(SRC), "dist")
STAMP = datetime.now().strftime("%Y%m%d")
PKG_NAME = f"gki-kernel-builder-{STAMP}"
STAGE = os.path.join(DIST, PKG_NAME)

INCLUDE_FILES = [
    "开始之前先看我.md",
    "快速指引.txt",
    "README.md",
    "LICENSE",
    "gkibuild.sh",
    "docker-run.sh",
    "Dockerfile",
    "build_kernel.sh",
    "build-gki.ps1",
    "启动编译.bat",
]

INCLUDE_DIRS = [".github", "config", "scripts", "security_patch", "zram"]


def main():
    if os.path.exists(STAGE):
        shutil.rmtree(STAGE)
    os.makedirs(STAGE, exist_ok=True)
    os.makedirs(DIST, exist_ok=True)

    n = 0
    for f in INCLUDE_FILES:
        p = os.path.join(SRC, f)
        if os.path.isfile(p):
            shutil.copy2(p, os.path.join(STAGE, f))
            n += 1
        else:
            print(f"  [跳过-缺失] {f}")

    for d in INCLUDE_DIRS:
        p = os.path.join(SRC, d)
        if os.path.isdir(p):
            shutil.copytree(p, os.path.join(STAGE, d))
            n += 1
        else:
            print(f"  [跳过-缺失] {d}/")

    zip_path = os.path.join(DIST, f"{PKG_NAME}.zip")
    if os.path.exists(zip_path):
        os.remove(zip_path)

    total = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, dirs, files in os.walk(STAGE):
            dirs[:] = [x for x in dirs if x not in (".git", "__pycache__")]
            for fn in sorted(files):
                fp = os.path.join(root, fn)
                arc = os.path.relpath(fp, DIST)
                z.write(fp, arc)
                total += os.path.getsize(fp)

    size_mb = os.path.getsize(zip_path) / 1048576
    print(f"\n打包完成: {zip_path}")
    print(f"包含 {n} 个顶层条目，压缩包 {size_mb:.2f} MB")


if __name__ == "__main__":
    main()
