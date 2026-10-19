# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright"]
# ///
"""Render the uadebate.com pages, and the cab pages its visitors reach
(home, sign-in, My page, account, a club), as an iPhone 15 against the
running dev stack (make dev:up) and fail if any page scrolls sideways.
cab's own full page list is checked in opendebate-cab.

    uv run tools/phone/phone_check.py [--shots DIR]

Signs in as $DEV_USER through cab's dev-only /dev/switch-user. The first run may
need the browser: uv run --with playwright playwright install chromium
"""
import argparse
import os
import subprocess
import sys

from playwright.sync_api import sync_playwright

CAB = "http://localhost:4000"
UA = "http://localhost:4001"
USER = os.environ["DEV_USER"]


def first(sql):
    out = subprocess.run(
        ["psql", "-d", "cab_gateway_dev", "-tAc", sql], capture_output=True, text=True
    ).stdout.strip()
    return out.splitlines()[0] if out else None


def pages():
    club = first("select uuid from clubs where archived_at is null order by id limit 1")
    found = [
        CAB + "/", CAB + "/signin", CAB + "/me", CAB + "/account", CAB + "/policy",
        UA + "/", UA + "/news", UA + "/calendar", UA + "/clubs", UA + "/about",
        UA + "/manage", UA + "/manage/calendar",
    ]
    if club:
        found += [f"{UA}/clubs/{club}", f"{CAB}/c/{club}"]
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shots", help="save a full-page screenshot of each page here")
    args = parser.parse_args()

    failures = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for scheme in ("light", "dark"):
            ctx = browser.new_context(**p.devices["iPhone 15"], color_scheme=scheme)
            page = ctx.new_page()
            page.goto(f"{CAB}/dev/switch-user?username={USER}", wait_until="networkidle")
            for url in pages():
                resp = page.goto(url, wait_until="networkidle")
                wide = page.evaluate("document.documentElement.scrollWidth - screen.width")
                status = resp.status if resp else 0
                ok = wide <= 0 and status < 500
                print(f"{'ok  ' if ok else 'FAIL'} {scheme:5} {status} +{max(wide, 0):>3}px  {url}")
                if not ok:
                    failures.append(url)
                if args.shots:
                    name = url.split("//", 1)[1].replace("/", "_").replace(":", "")
                    page.screenshot(path=f"{args.shots}/{name}-{scheme}.png", full_page=True)
            ctx.close()
        browser.close()

    if failures:
        print(f"\n{len(failures)} page(s) scroll sideways or failed on an iPhone")
        sys.exit(1)
    print("\nevery page fits an iPhone")


if __name__ == "__main__":
    main()
