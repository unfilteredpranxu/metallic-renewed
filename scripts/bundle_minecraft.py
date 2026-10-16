#!/usr/bin/env python3
"""
Pre-bundles Minecraft client JAR, version JSON, libraries, and assets
into ios-app/bundled_* directories for bundling into the IPA payload.
"""

import os
import sys
import json
import hashlib
import argparse
import urllib.request
import zipfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

def download_file(url, target_path, expected_sha1=None, max_retries=3):
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    
    # Check if already downloaded and valid
    if os.path.exists(target_path) and os.path.getsize(target_path) > 0:
        if expected_sha1:
            with open(target_path, "rb") as f:
                current_sha1 = hashlib.sha1(f.read()).hexdigest()
            if current_sha1.lower() == expected_sha1.lower():
                return True
        else:
            return True

    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Metallic-Bundler)"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
            
            if expected_sha1:
                calc_sha1 = hashlib.sha1(data).hexdigest()
                if calc_sha1.lower() != expected_sha1.lower():
                    print(f"[WARN] SHA1 mismatch for {url} (attempt {attempt+1}/{max_retries})")
                    continue
            
            temp_path = target_path + ".tmp"
            with open(temp_path, "wb") as f:
                f.write(data)
            os.replace(temp_path, target_path)
            return True
        except Exception as e:
            if attempt + 1 == max_retries:
                print(f"[ERROR] Failed to download {url}: {e}")
                return False
            time.sleep(1.0)
    return False

def main():
    parser = argparse.ArgumentParser(description="Pre-bundle Minecraft assets and libraries")
    parser.add_argument("--version", default="26.2", help="Minecraft version to bundle (default: 26.2)")
    parser.add_argument("--target-dir", default="ios-app", help="Base directory of ios-app")
    parser.add_argument("--skip-assets", action="store_true", help="Skip downloading asset objects")
    parser.add_argument("--workers", type=int, default=32, help="Number of download worker threads")
    args = parser.parse_args()

    version_id = args.version
    base_dir = os.path.abspath(args.target_dir)
    bundled_libs_dir = os.path.join(base_dir, "bundled_libraries")
    bundled_vers_dir = os.path.join(base_dir, "bundled_versions", version_id)
    bundled_assets_dir = os.path.join(base_dir, "bundled_assets")
    artifacts_dir = os.path.join(base_dir, "artifacts")

    os.makedirs(bundled_libs_dir, exist_ok=True)
    os.makedirs(bundled_vers_dir, exist_ok=True)
    os.makedirs(bundled_assets_dir, exist_ok=True)
    os.makedirs(artifacts_dir, exist_ok=True)

    print(f"=== Bundling Minecraft {version_id} ===")
    print(f"Target directory: {base_dir}")

    # 1. Fetch version manifest
    print("[1/5] Fetching Mojang version manifest...")
    manifest_url = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
    req = urllib.request.Request(manifest_url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        manifest = json.loads(resp.read().decode("utf-8"))

    version_meta = None
    for v in manifest.get("versions", []):
        if v.get("id") == version_id:
            version_meta = v
            break

    if not version_meta:
        print(f"[ERROR] Version {version_id} not found in version manifest!")
        sys.exit(1)

    # 2. Fetch version JSON
    version_json_url = version_meta["url"]
    version_json_path = os.path.join(bundled_vers_dir, f"{version_id}.json")
    print(f"[2/5] Downloading version JSON: {version_json_url}")
    req = urllib.request.Request(version_json_url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        version_data = json.loads(resp.read().decode("utf-8"))
    with open(version_json_path, "w", encoding="utf-8") as f:
        json.dump(version_data, f, indent=2)

    # 3. Fetch client JAR
    client_info = version_data.get("downloads", {}).get("client", {})
    client_url = client_info.get("url")
    client_sha1 = client_info.get("sha1")
    client_jar_path = os.path.join(bundled_vers_dir, f"{version_id}.jar")
    print(f"[3/5] Downloading client JAR: {client_url} ({client_info.get('size', 0) / (1024*1024):.2f} MB)")
    if not download_file(client_url, client_jar_path, client_sha1):
        print("[ERROR] Failed to download client JAR!")
        sys.exit(1)
    print("  -> Client JAR verified successfully.")

    # 4. Fetch libraries
    libraries = version_data.get("libraries", [])
    print(f"[4/5] Preparing to download {len(libraries)} libraries...")
    lib_tasks = []
    for lib in libraries:
        name = lib.get("name", "")
        downloads = lib.get("downloads", {})
        artifact = downloads.get("artifact")

        if lib.get("natives") or downloads.get("classifiers"):
            continue

        if not artifact and ":" in name:
            parts = name.split(":")
            if len(parts) >= 3:
                rel_path = f"{parts[0].replace('.', '/')}/{parts[1]}/{parts[2]}/{parts[1]}-{parts[2]}.jar"
                prefix = lib.get("url") or "https://libraries.minecraft.net/"
                if not prefix.endswith("/"):
                    prefix += "/"
                url = prefix + rel_path
                sha1 = lib.get("checksums", [None])[0] if lib.get("checksums") else None
                dest = os.path.join(bundled_libs_dir, rel_path)
                lib_tasks.append((url, dest, sha1))
        elif artifact:
            rel_path = artifact.get("path")
            url = artifact.get("url")
            sha1 = artifact.get("sha1")
            if rel_path and url:
                dest = os.path.join(bundled_libs_dir, rel_path)
                lib_tasks.append((url, dest, sha1))

    print(f"  -> Downloading {len(lib_tasks)} applicable libraries with {args.workers} threads...")
    completed_libs = 0
    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {executor.submit(download_file, url, dest, sha1): (url, dest) for (url, dest, sha1) in lib_tasks}
        for future in as_completed(futures):
            res = future.result()
            if res:
                completed_libs += 1
            else:
                url, dest = futures[future]
                print(f"[WARN] Failed library download: {url}")

    print(f"  -> Finished downloading {completed_libs}/{len(lib_tasks)} libraries.")

    # Create standalone bundled_libraries.zip artifact
    zip_dest = os.path.join(artifacts_dir, "bundled_libraries.zip")
    print(f"  -> Packaging {zip_dest}...")
    with zipfile.ZipFile(zip_dest, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(bundled_libs_dir):
            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, bundled_libs_dir)
                zf.write(full_path, os.path.join("libraries", rel_path))
    print(f"  -> bundled_libraries.zip created ({os.path.getsize(zip_dest) / (1024*1024):.2f} MB)")

    # 5. Fetch asset index and assets
    asset_index = version_data.get("assetIndex", {})
    asset_index_id = asset_index.get("id")
    asset_index_url = asset_index.get("url")
    if asset_index_url:
        print(f"[5/5] Downloading asset index {asset_index_id}...")
        index_dir = os.path.join(bundled_assets_dir, "indexes")
        os.makedirs(index_dir, exist_ok=True)
        index_path = os.path.join(index_dir, f"{asset_index_id}.json")
        req = urllib.request.Request(asset_index_url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            asset_index_data = json.loads(resp.read().decode("utf-8"))
        with open(index_path, "w", encoding="utf-8") as f:
            json.dump(asset_index_data, f, indent=2)

        if not args.skip_assets:
            objects = asset_index_data.get("objects", {})
            print(f"  -> Preparing {len(objects)} asset objects...")
            asset_tasks = []
            for name, obj in objects.items():
                if name.endswith("/minecraft.icns"):
                    continue
                h = obj.get("hash")
                if not h or len(h) < 2:
                    continue
                pathname = f"{h[:2]}/{h}"
                url = f"https://resources.download.minecraft.net/{pathname}"
                dest = os.path.join(bundled_assets_dir, "objects", pathname)
                asset_tasks.append((url, dest, h))

            print(f"  -> Downloading {len(asset_tasks)} asset objects with {args.workers} threads...")
            completed_assets = 0
            with ThreadPoolExecutor(max_workers=args.workers) as executor:
                futures = {executor.submit(download_file, url, dest, sha1): dest for (url, dest, sha1) in asset_tasks}
                for future in as_completed(futures):
                    if future.result():
                        completed_assets += 1
                    if completed_assets % 1000 == 0:
                        print(f"     Downloaded {completed_assets}/{len(asset_tasks)} assets...")

            print(f"  -> Finished downloading {completed_assets}/{len(asset_tasks)} asset objects.")
        else:
            print("  -> Skipping asset objects (--skip-assets specified).")

    print("\n=== Pre-bundling Complete ===")

if __name__ == "__main__":
    main()
