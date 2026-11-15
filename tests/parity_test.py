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

if failures:
    print("PARITY FAIL\n" + "\n".join(failures))
    sys.exit(1)
print(f"parity ok: {len(py)} players, addon and bot agree: {py}")
