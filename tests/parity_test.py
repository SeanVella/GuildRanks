#!/usr/bin/env python3
"""Checks that the Discord bot computes exactly the same Guild scores as the addon.

Run the Lua tests first (they write tests/out/export.json and lua_scores.json):
    lua5.1 tests/run_all.lua scoring && python3 tests/parity_test.py
"""
import importlib.util
import json
import os
import sys
from datetime import date, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("bot", os.path.join(ROOT, "automation", "bot", "guild_ranks_bot.py"))
bot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bot)

out = os.path.join(ROOT, "tests", "out")
with open(os.path.join(out, "export.json"), encoding="utf-8") as f:
    export = json.load(f)
with open(os.path.join(out, "lua_scores.json"), encoding="utf-8") as f:
    lua = json.load(f)

name, entries = bot.pick_guild([export], "Froga")
players, rules = bot.merge_exports(entries)
today = date.fromisoformat(lua["today"])
this_start = bot.week_start(today, rules.get("resetDay") or 4)
scores = bot.compute_scores(players, this_start - timedelta(days=7), this_start - timedelta(days=1), rules)
py = {e["key"]: e["score"] for e in scores}

failures = []
if py != lua["scores"]:
    failures.append(f"scores differ:\n  addon: {lua['scores']}\n  bot:   {py}")
# the weekly post must build without errors from the same data
payloads = bot.build_weekly(players, rules, today, 5, name, "parity test")
if not payloads or "embeds" not in payloads[0]:
    failures.append("weekly post did not build")

# ---- daily post ----------------------------------------------------------
import argparse
import tempfile

day = date(2026, 11, 15)  # the test guild played on Sunday 15 Nov (last week)
best = scores[0]
daily = bot.build_daily(players, rules, day, ("player",), name, "test")
if not daily or daily[0]["embeds"][0]["title"] != "\u2B50 Player of the day":
    failures.append(f"daily post did not build: {daily}")
elif f"**{best['name']}**" not in daily[0]["embeds"][0]["description"]:
    failures.append(f"player of the day should be {best['name']}: {daily[0]['embeds'][0]['description']}")
full = bot.build_daily(players, rules, day, bot.DAILY_SECTIONS, name, "test")
titles = [e["title"] for e in full[0]["embeds"]] if full else []
if not any("Top 3" in t for t in titles) or not any("Wooden spoon" in t for t in titles):
    failures.append(f"daily post with all sections is missing parts: {titles}")
for e in (full[0]["embeds"] if full else []):
    if len(e.get("description", "")) > 4000 or len(e.get("fields", [])) > 25:
        failures.append("daily embed too big for Discord")
if bot.build_daily(players, rules, day, ("player",), name, "", min_players=len(scores) + 1) != []:
    failures.append("quiet day (too few players) should not post")
if bot.build_daily(players, rules, date(2026, 11, 1), ("player",), name, "") != []:
    failures.append("a day without data should not post")

# posting slot: before 09:00 it is still yesterday's slot
tz = bot.ZoneInfo("Europe/Malta")
if bot.daily_target(bot.datetime(2026, 11, 18, 8, 59, tzinfo=tz), (9, 0)).day != 17:
    failures.append("08:59 should belong to yesterday's slot")
if bot.daily_target(bot.datetime(2026, 11, 18, 9, 0, tzinfo=tz), (9, 0)).day != 18:
    failures.append("09:00 should be today's slot")

# end to end: posts once per day, never twice
posted = []
bot.post_discord = lambda webhook, payloads: posted.append(payloads)
real_datetime = bot.datetime


class FakeNow(real_datetime):
    @classmethod
    def now(cls, tz=None):
        return real_datetime(2026, 11, 16, 9, 5, tzinfo=tz)


bot.datetime = FakeNow
with tempfile.TemporaryDirectory() as tmp:
    os.makedirs(os.path.join(tmp, "uploads"))
    with open(os.path.join(tmp, "uploads", "sean.json"), "w", encoding="utf-8") as f:
        json.dump(export, f)
    ns = argparse.Namespace(tz="Europe/Malta", daily_time="09:00", sections="player", state=os.path.join(tmp, "state.json"),
                            force=False, dry_run=False, uploads=os.path.join(tmp, "uploads"), guild="Froga",
                            today="2026-11-16", webhook="https://example.invalid/hook", min_players=2)
    bot.cmd_daily(ns)
    bot.cmd_daily(ns)
    if len(posted) != 1:
        failures.append(f"daily command should post exactly once, posted {len(posted)} times")
    with open(ns.state) as f:
        st = json.load(f)
    if st.get("day") != "2026-11-15" or not st.get("posted"):
        failures.append(f"daily state wrong: {st}")
bot.datetime = real_datetime

if failures:
    print("PARITY FAIL\n" + "\n".join(failures))
    sys.exit(1)
print(f"parity ok: {len(py)} players, addon and bot agree: {py}; daily post ok")
