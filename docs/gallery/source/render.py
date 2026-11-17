import sys, asyncio
from pathlib import Path
from playwright.async_api import async_playwright
async def main():
    out = Path(__file__).parent / "out"
    files = sorted(out.glob("*.html"))
    if len(sys.argv) > 1: files = [f for f in files if any(a in f.name for a in sys.argv[1:])]
    async with async_playwright() as p:
        b = await p.chromium.launch(channel="chrome")
        pg = await b.new_page(viewport={"width": 1920, "height": 1080})
        for f in files:
            await pg.goto(f.as_uri()); await pg.wait_for_timeout(300)
            await pg.screenshot(path=str(f.with_suffix(".png")))
            print("rendered", f.name)
        await b.close()
asyncio.run(main())
