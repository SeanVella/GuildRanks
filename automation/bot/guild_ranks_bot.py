#!/usr/bin/env python3
"""Guild Ranks weekly and daily Discord posts (optional automation; runs in GitHub Actions).

Officers' PCs upload their Guild Ranks export to uploads/ in the guild's repository.
GitHub Actions workflows merge all uploads (keeping the most complete copy of each
player's day) and post to Discord:
  weekly  every Wednesday evening: last week's results, MVP and Wooden spoon
  daily   every morning: yesterday's Player of the day (optionally top 3, the
          week so far and the Wooden spoon of the day); skipped on quiet days

Only the Python standard library is used.

Commands:
  python bot/guild_ranks_bot.py weekly --guild "My Guild-Realm" [--force] [--dry-run]
  python bot/guild_ranks_bot.py daily [--sections player,top,week,spoon] [--force] [--dry-run]
  python bot/guild_ranks_bot.py preview --sv GuildRanks.lua [--sv other.json] [--guild NAME] [--today 2026-11-18]
  python bot/guild_ranks_bot.py preview --daily --sv GuildRanks.lua [--sections player,top]
  python bot/guild_ranks_bot.py post --sv GuildRanks.lua --webhook URL
"""
import argparse
import glob
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

GOLD_SOURCES = ["loot", "quest", "vendor", "ah", "mail", "trade", "other"]

# key, label, format, lower-is-better, emoji (per-hour boards in the weekly post)
METRICS = [
    ("gold", "Gold earned", "money", False, "\U0001FA99"),
    ("loot", "Loot value", "money", False, "\U0001F4B0"),
    ("xp", "Experience", "num", False, "✨"),
    ("levels", "Levels gained", "levels", False, "\U0001F4C8"),
    ("damage", "Damage done", "num", False, "⚔️"),
    ("healing", "Healing done", "num", False, "\U0001F49A"),
    ("kills", "Kills", "num", False, "\U0001F480"),
    ("quests", "Quests completed", "num", False, "\U0001F4DC"),
    ("bosses", "Bosses killed", "num", False, "\U0001F451"),
    ("dungeons", "Dungeon/raid runs", "num", False, "\U0001F3F0"),
    ("gathers", "Gathering", "num", False, "\U0001F33F"),
    ("crafts", "Items crafted", "num", False, "\U0001F528"),
    ("deaths", "Fewest deaths", "num", True, "⚰️"),
]

# Guild score categories (must match ns.SCORE_CATEGORIES in Core.lua)
SCORE_CATEGORIES = [
    ("gold", "gold", False),
    ("levels", "levels", False),
    ("combat", "combat", False),
    ("quests", "quests", False),
    ("kills", "kills", False),
    ("runs", "bosses and runs", False),
    ("craft", "gathering and crafting", False),
    ("deaths", "fewest deaths", True),
]

WEEKDAYS = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}
MEDALS = ["\U0001F947", "\U0001F948", "\U0001F949"]
COLOR_BOARD, COLOR_MVP, COLOR_SPOON = 0x3BA55D, 0xEF9F27, 0x888780


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


# --------------------------------------------------------------------------
# Reading SavedVariables
# --------------------------------------------------------------------------
def lua_unescape(raw: bytes) -> bytes:
    out = bytearray()
    i, n = 0, len(raw)
    simple = {ord("n"): b"\n", ord("t"): b"\t", ord("r"): b"\r", ord("\\"): b"\\",
              ord('"'): b'"', ord("'"): b"'", ord("\n"): b"\n", ord("a"): b"\a", ord("b"): b"\b"}
    while i < n:
        c = raw[i]
        if c != 0x5C:
            out.append(c)
            i += 1
            continue
        nxt = raw[i + 1] if i + 1 < n else None
        if nxt is not None and 0x30 <= nxt <= 0x39:
            j = i + 1
            while j < n and j < i + 4 and 0x30 <= raw[j] <= 0x39:
                j += 1
            out.append(int(raw[i + 1:j]) & 0xFF)
            i = j
        elif nxt in simple:
            out += simple[nxt]
            i += 2
        else:
            out.append(c)
            i += 1
    return bytes(out)


def parse_export(data: bytes) -> dict:
    m = re.search(rb'\["exportJSON"\]\s*=\s*"((?:[^"\\]|\\.)*)"', data, re.S)
    if not m:
        raise ValueError("no Guild Ranks export in this file yet (log out or /reload in game once)")
    export = json.loads(lua_unescape(m.group(1)).decode("utf-8"))
    if not isinstance(export, dict) or export.get("addon") != "GuildRanks":
        raise ValueError("not a Guild Ranks export")
    return export


def as_dict(v):
    return v if isinstance(v, dict) else {}


def pick_guild(exports, wanted=None):
    """Each export can hold several guilds (one per guild your characters are in).
    Returns (guild display name, list of that guild's entries across all exports)."""
    entries = [g for ex in exports for g in (ex.get("guilds") or []) if isinstance(g, dict)]
    keys = sorted({g.get("key") for g in entries if g.get("key")})
    if wanted:
        w = wanted.strip().lower()
        chosen = [g for g in entries if (g.get("key") or "").lower() == w or (g.get("name") or "").lower() == w]
        if not chosen:
            raise SystemExit(f"Guild '{wanted}' not found in the uploads. Available: {', '.join(keys) or 'none'}")
    elif len(keys) == 1:
        chosen = entries
    elif not keys:
        raise SystemExit("No guild data in the uploads yet.")
    else:
        raise SystemExit(f"The uploads contain several guilds; set GUILD to one of: {', '.join(keys)}")
    return chosen[0].get("name") or chosen[0].get("key"), chosen


def merge_exports(exports):
    """Combine one guild's entries from several members' uploads. For each player
    and day, keep the copy with the most play time (the most complete one).
    Players excluded by the guild's managers are left out."""
    players, rules, rules_version = {}, {}, -1
    for ex in exports:
        r = as_dict(ex.get("rules"))
        if (r.get("version") or 0) >= rules_version:
            rules_version, rules = r.get("version") or 0, r
        for p in ex.get("players") or []:
            key = p.get("key") or p.get("name")
            if not key:
                continue
            cur = players.setdefault(key, {"key": key, "name": p.get("name") or key.split("-")[0],
                                           "class": p.get("class"), "level": 0, "days": {}, "all": {}})
            cur["level"] = max(cur["level"] or 0, p.get("level") or 0)
            cur["class"] = cur["class"] or p.get("class")
            for day, b in as_dict(p.get("days")).items():
                b = as_dict(b)
                if b.get("playtime", 0) > cur["days"].get(day, {}).get("playtime", 0):
                    cur["days"][day] = b
            a = as_dict(p.get("all"))
            if a.get("playtime", 0) > cur["all"].get("playtime", 0):
                cur["all"] = a
    excluded = rules.get("excluded")
    for key in (excluded if isinstance(excluded, list) else []):
        players.pop(key, None)
    return players, rules


# --------------------------------------------------------------------------
# Weeks and totals
# --------------------------------------------------------------------------
def realm_today(now: datetime, rules) -> date:
    """The guild's current day: a day runs from the reset hour to the same hour next day."""
    hour = min(23, max(0, int(rules.get("resetHour") or 0)))
    return (now - timedelta(hours=hour)).date()


def week_start(today: date, reset_day: int) -> date:
    """reset_day uses WoW numbering: 1 = Sunday ... 7 = Saturday."""
    wow_wday = (today.weekday() + 1) % 7 + 1
    return today - timedelta(days=(wow_wday - reset_day) % 7)


def period_bucket(player, start: date, end: date):
    total = {}
    for day, b in player["days"].items():
        try:
            d = date.fromisoformat(day)
        except ValueError:
            continue
        if start <= d <= end:
            for k, v in b.items():
                if isinstance(v, (int, float)):
                    total[k] = total.get(k, 0) + v
    return total


def metric_total(bucket, key, rules):
    gold_rules = as_dict(rules.get("gold"))
    if key == "gold":
        return sum(bucket.get("g_" + s, 0) for s in GOLD_SOURCES if gold_rules.get(s, True))
    if key == "loot":
        return bucket.get("lv_auction" if rules.get("itemValue") == "auction" else "lv_vendor", 0)
    if key == "levels":
        return bucket.get("mlevels", 0) / 1000
    return bucket.get(key, 0)


# --------------------------------------------------------------------------
# Guild score (same rules as Core.lua)
# --------------------------------------------------------------------------
def placement_scores(entries, get_value, lower=False):
    scores, lst = {}, []
    for e in entries:
        v = get_value(e)
        if lower or v > 0:
            lst.append((e["key"], v))
        else:
            scores[e["key"]] = 0.0
    lst.sort(key=lambda t: t[1] if lower else -t[1])
    n, i = len(lst), 0
    while i < n:
        j = i
        while j + 1 < n and lst[j + 1][1] == lst[i][1]:
            j += 1
        pos = (i + j) / 2
        if lower:
            s = 100.0 if n <= 1 else 100.0 * (n - 1 - pos) / (n - 1)
        else:
            s = 100.0 * (n - pos) / n
        for k in range(i, j + 1):
            scores[lst[k][0]] = s
        i = j + 1
    return scores


def category_value(cat, b, rules):
    if cat == "gold":
        return metric_total(b, "gold", rules)
    if cat == "levels":
        return metric_total(b, "levels", rules)
    if cat == "runs":
        return b.get("bosses", 0) + b.get("dungeons", 0)
    if cat == "craft":
        return b.get("gathers", 0) + b.get("crafts", 0)
    return b.get(cat, 0)


def compute_scores(players, start, end, rules):
    min_secs = max(60, (rules.get("minMinutes") or 0) * 60)
    entries = []
    for p in players.values():
        b = period_bucket(p, start, end)
        secs = b.get("playtime", 0)
        if secs >= min_secs:
            entries.append({"key": p["key"], "name": p["name"], "level": p.get("level"),
                            "bucket": b, "playtime": secs, "hours": secs / 3600, "cats": {}})
    if not entries:
        return entries
    for cat, _label, lower in SCORE_CATEGORIES:
        if cat == "combat":
            sd = placement_scores(entries, lambda e: e["bucket"].get("damage", 0) / e["hours"])
            sh = placement_scores(entries, lambda e: e["bucket"].get("healing", 0) / e["hours"])
            for e in entries:
                e["cats"]["combat"] = max(sd[e["key"]], sh[e["key"]])
        else:
            s = placement_scores(entries, lambda e, c=cat: category_value(c, e["bucket"], rules) / e["hours"], lower)
            for e in entries:
                e["cats"][cat] = s[e["key"]]
    for e in entries:
        e["score"] = math.floor(sum(e["cats"].values()) / len(SCORE_CATEGORIES) + 0.5)
    entries.sort(key=lambda e: (-e["score"], e["name"]))
    return entries


def award_notes(entry, entries):
    firsts, lasts = [], []
    for cat, label, _lower in SCORE_CATEGORIES:
        vals = [e["cats"][cat] for e in entries]
        if entry["cats"][cat] >= 100 and max(vals) > min(vals):
            firsts.append(label)
        if entry["cats"][cat] == min(vals) and max(vals) > min(vals):
            lasts.append(label)
    return firsts, lasts


def join_words(words):
    if len(words) == 1:
        return words[0]
    if any(" and " in w for w in words):  # e.g. "bosses and runs": "and" would be ambiguous
        return " \u00b7 ".join(words)
    return ", ".join(words[:-1]) + " and " + words[-1]


# --------------------------------------------------------------------------
# Formatting and the weekly post
# --------------------------------------------------------------------------
def fmt_money(copper):
    copper = int(round(copper))
    g, s, c = copper // 10000, (copper % 10000) // 100, copper % 100
    return f"{g:,}g {s}s" if g else (f"{s}s {c}c" if s else f"{c}c")


def fmt_time(secs):
    secs = int(secs)
    h, m = secs // 3600, (secs % 3600) // 60
    return f"{h}h {m:02d}m" if h else f"{m}m"


def fmt_rate(fmt, v):
    if fmt == "money":
        s = fmt_money(v)
    elif fmt == "levels":
        s = f"{v:.2f}"
    elif v >= 1e6:
        s = f"{v / 1e6:.2f}M"
    elif v >= 1e4:
        s = f"{v / 1e3:.1f}K"
    elif v < 100:
        s = f"{v:.1f}"
    else:
        s = f"{v:,.0f}"
    return s + "/h"


def board_lines(rows, value_fmt):
    lines = []
    for i, r in enumerate(rows):
        place = MEDALS[i] if i < len(MEDALS) else f"`{i + 1}.`"
        lvl = f" ({r['level']})" if r.get("level") else ""
        lines.append(f"{place} **{r['name']}**{lvl} — {value_fmt(r)}")
    return "\n".join(lines)


def metric_board(players, start, end, rules, metric, top):
    key, _label, fmt, lower, _emoji = metric
    min_secs = max(60, (rules.get("minMinutes") or 0) * 60)
    rows = []
    for p in players.values():
        b = period_bucket(p, start, end)
        secs = b.get("playtime", 0)
        if secs < min_secs:
            continue
        total = metric_total(b, key, rules)
        if total <= 0 and not lower:
            continue
        rows.append({"name": p["name"], "level": p.get("level"), "value": total / (secs / 3600)})
    rows.sort(key=lambda r: (r["value"] if lower else -r["value"], r["name"]))
    return rows[:top]


def build_weekly(players, rules, today: date, top=5, guild="Guild", source_note=""):
    reset_day = rules.get("resetDay") or 4
    this_start = week_start(today, reset_day)
    start, end = this_start - timedelta(days=7), this_start - timedelta(days=1)
    scores = compute_scores(players, start, end, rules)
    min_min = rules.get("minMinutes") or 0

    header = (f"**<{guild}> weekly results — {start.strftime('%a %d %b')} to {end.strftime('%a %d %b')}**\n"
              f"{len(scores)} members qualified (at least {min_min} min played)")
    if source_note:
        header += f"\n-# {source_note}"
    if not scores:
        return [{"content": header + "\n\nNobody qualified this week."}]

    embeds = []
    mvp = scores[0]
    firsts, _ = award_notes(mvp, scores)
    desc = f"**{mvp['name']}** ({mvp.get('level') or '?'}) — Guild score **{mvp['score']}**"
    if firsts:
        desc += f"\n1st in {join_words(firsts)}"
    embeds.append({"title": "\U0001F3C6 MVP of the week", "description": desc, "color": COLOR_MVP})
    if len(scores) >= 2 and rules.get("showSpoon", True):
        spoon = scores[-1]
        _, lasts = award_notes(spoon, scores)
        desc = f"**{spoon['name']}** ({spoon.get('level') or '?'}) — Guild score **{spoon['score']}**"
        if lasts:
            desc += f"\nLast in {join_words(lasts)}"
        embeds.append({"title": "\U0001F944 Wooden spoon of the week", "description": desc, "color": COLOR_SPOON})

    # Weekly challenge winner and guild goal (set by the guild's officers in game)
    metric_by_key = {m[0]: m for m in METRICS}
    cm = metric_by_key.get(rules.get("challengeMetric") or "")
    if cm:
        rows = metric_board(players, start, end, rules, cm, 1)
        if rows:
            prize = f"\nPrize: {rules['challengePrize']}" if rules.get("challengePrize") else ""
            embeds.append({"title": f"\U0001F3AF Weekly challenge: {cm[1]} per hour", "color": COLOR_MVP,
                           "description": f"Winner: **{rows[0]['name']}** \u2014 {fmt_rate(cm[2], rows[0]['value'])}{prize}"})
    gm = metric_by_key.get(rules.get("goalMetric") or "")
    target = rules.get("goalTarget") or 0
    if gm and target > 0:
        total = sum(metric_total(period_bucket(p, start, end), gm[0], rules) for p in players.values())
        done = "\u2705 reached!" if total >= target else f"{int(100 * total / target)}%"
        fmt = (lambda v: fmt_money(v)) if gm[2] == "money" else (lambda v: f"{v:,.0f}")
        embeds.append({"title": f"\U0001F91D Guild goal: {gm[1]}", "color": COLOR_BOARD,
                       "description": f"{fmt(total)} / {fmt(target)} ({done})"})

    embeds.append({"title": "\U0001F3C5 Guild score", "color": COLOR_BOARD,
                   "description": board_lines(scores[:top], lambda r: f"{r['score']}")})
    for metric in METRICS:
        rows = metric_board(players, start, end, rules, metric, top)
        # skip boards with nothing to show (e.g. nobody died: everyone 0)
        if rows and not (metric[3] and len({round(r["value"], 6) for r in rows}) == 1):
            embeds.append({"title": f"{metric[4]} {metric[1]} per hour", "color": COLOR_BOARD,
                           "description": board_lines(rows, lambda r, f=metric[2]: fmt_rate(f, r["value"]))})

    payloads, batch, size = [], [], len(header)
    for e in embeds:
        e_size = len(e["title"]) + len(e["description"])
        if batch and (len(batch) == 10 or size + e_size > 5500):
            payloads.append({"embeds": batch})
            batch, size = [], 0
        batch.append(e)
        size += e_size
    payloads.append({"embeds": batch})
    payloads[0]["content"] = header
    return payloads


# --------------------------------------------------------------------------
# The daily post (yesterday's results)
# --------------------------------------------------------------------------
DAILY_SECTIONS = ("player", "top", "week", "spoon")
DAILY_METRICS = ("gold", "xp", "damage", "quests", "levels")
COLOR_DAY = 0xF2B934


def build_daily(players, rules, day: date, sections=("player",), guild="Guild", source_note="",
                min_players=2, top=3):
    """Payloads for one day's results, or [] when fewer than min_players qualified."""
    scores = compute_scores(players, day, day, rules)
    if len(scores) < max(1, min_players):
        return []
    played, total_secs = 0, 0
    for p in players.values():
        secs = period_bucket(p, day, day).get("playtime", 0)
        if secs > 0:
            played += 1
            total_secs += secs
    header = f"**<{guild}> daily results: {day.strftime('%a %d %b')}**\n{played} member{'' if played == 1 else 's'} played"
    if rules.get("showPlaytime", True) is not False:
        header += f" \u00b7 {fmt_time(total_secs)} in total"
    if source_note:
        header += f"\n-# {source_note}"

    embeds = []
    if "player" in sections:
        best = scores[0]
        firsts, _ = award_notes(best, scores)
        desc = f"**{best['name']}** ({best.get('level') or '?'}) \u2014 Guild score **{best['score']}**"
        if firsts:
            desc += f"\n1st in {join_words(firsts)}"
        embeds.append({"title": "\u2B50 Player of the day", "description": desc, "color": COLOR_DAY})
    if "spoon" in sections and rules.get("showSpoon", True) and len(scores) >= 2:
        last = scores[-1]
        embeds.append({"title": "\U0001F944 Wooden spoon of the day", "color": COLOR_SPOON,
                       "description": f"**{last['name']}** ({last.get('level') or '?'}) \u2014 Guild score **{last['score']}**"})
    if "top" in sections:
        fields = []
        by_key = {m[0]: m for m in METRICS}
        for key in DAILY_METRICS:
            metric = by_key[key]
            rows = metric_board(players, day, day, rules, metric, top)
            if rows:
                fields.append({"name": f"{metric[4]} {metric[1]} per hour", "inline": True,
                               "value": board_lines(rows, lambda r, f=metric[2]: fmt_rate(f, r["value"]))})
        if fields:
            embeds.append({"title": f"\U0001F3C5 Top {top} of the day", "color": COLOR_BOARD, "fields": fields})
    if "week" in sections:
        start = week_start(day, rules.get("resetDay") or 4)  # the week the posted day belongs to
        lines = []
        cm = {m[0]: m for m in METRICS}.get(rules.get("challengeMetric") or "")
        if cm:
            rows = metric_board(players, start, day, rules, cm, 1)
            if rows:
                prize = f" \u00b7 Prize: {rules['challengePrize']}" if rules.get("challengePrize") else ""
                lines.append(f"Challenge ({cm[1]} per hour): **{rows[0]['name']}** leads{prize}")
        gm = {m[0]: m for m in METRICS}.get(rules.get("goalMetric") or "")
        target = rules.get("goalTarget") or 0
        if gm and target > 0:
            total = sum(metric_total(period_bucket(p, start, day), gm[0], rules) for p in players.values())
            fmt = (lambda v: fmt_money(v)) if gm[2] == "money" else (lambda v: f"{v:,.0f}")
            lines.append(f"Guild goal ({gm[1]}): {fmt(total)} / {fmt(target)} ({min(100, int(100 * total / target))}%)")
        if lines:
            embeds.append({"title": "\U0001F3AF This week so far", "color": COLOR_BOARD, "description": "\n".join(lines)})

    min_min = rules.get("minMinutes") or 0
    note = f"Members with the addon and at least {min_min} min played that day \u00b7 tracked with Guild Ranks"
    if embeds:
        embeds[-1]["footer"] = {"text": note}
        return [{"content": header, "embeds": embeds}]
    return [{"content": header + f"\n-# {note}"}]


def daily_target(now, post_time):
    """Most recent daily posting slot (e.g. 09:00) at or before now."""
    target = now.replace(hour=post_time[0], minute=post_time[1], second=0, microsecond=0)
    if target > now:
        target -= timedelta(days=1)
    return target


# --------------------------------------------------------------------------
# Discord
# --------------------------------------------------------------------------
def post_discord(webhook, payloads):
    for payload in payloads:
        body = json.dumps({**payload, "username": "Guild Ranks", "allowed_mentions": {"parse": []}}).encode()
        for _attempt in range(5):
            req = urllib.request.Request(webhook, data=body, method="POST", headers={
                "Content-Type": "application/json", "User-Agent": "GuildRanks bot (GitHub Actions, 1.0)"})
            try:
                with urllib.request.urlopen(req, timeout=30):
                    break
            except urllib.error.HTTPError as err:
                if err.code == 429:
                    time.sleep(float(json.loads(err.read() or b"{}").get("retry_after", 2)) + 0.5)
                    continue
                raise RuntimeError(f"Discord rejected the message: HTTP {err.code} {err.read()[:300]!r}")
        else:
            raise RuntimeError("Discord kept rate-limiting the webhook")
        time.sleep(1)

# --------------------------------------------------------------------------
# Loading uploads
# --------------------------------------------------------------------------
def load_file(path):
    """Accepts the uploader's .json export or a raw SavedVariables .lua file."""
    with open(path, "rb") as f:
        data = f.read()
    if path.lower().endswith(".json"):
        export = json.loads(data.decode("utf-8-sig"))
        if not isinstance(export, dict) or export.get("addon") != "GuildRanks":
            raise ValueError("not a Guild Ranks export")
        return export
    return parse_export(data)


def load_files(paths):
    exports, names = [], []
    for p in paths:
        try:
            exports.append(load_file(p))
            names.append(os.path.splitext(os.path.basename(p))[0])
        except (OSError, ValueError) as err:
            log(f"skipping {p}: {err}")
    return exports, names


def source_note(exports, names, tz):
    newest = max((e.get("generatedAt") or 0 for e in exports), default=0)
    note = f"Data from {len(names)} upload(s) ({', '.join(sorted(names))})"
    if newest:
        note += f", newest {datetime.fromtimestamp(newest, tz).strftime('%a %d %b %H:%M')}"
    return note


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------
def last_target(now, post_day, post_time):
    """Most recent posting slot (e.g. Wednesday 20:00) at or before now."""
    target = now.replace(hour=post_time[0], minute=post_time[1], second=0, microsecond=0)
    target -= timedelta(days=(now.weekday() - post_day) % 7)
    if target > now:
        target -= timedelta(days=7)
    return target


def cmd_weekly(args):
    tz = ZoneInfo(args.tz)
    now = datetime.now(tz)
    post_day = WEEKDAYS[args.post_day.strip().lower()[:3]]
    hh, mm = args.post_time.split(":")
    target = last_target(now, post_day, (int(hh), int(mm)))

    try:
        with open(args.state) as f:
            state = json.load(f)
    except (OSError, ValueError):
        state = {}

    if not args.force:
        if state.get("last_target") == target.isoformat():
            log(f"already posted for the {target:%a %d %b %H:%M} slot, nothing to do")
            return
        if now - target > timedelta(days=2):
            log(f"the {target:%a %d %b %H:%M} slot is more than 2 days old, skipping it")
            if not args.dry_run:
                state["last_target"] = target.isoformat()
                save_state(args.state, state)
            return

    paths = sorted(glob.glob(os.path.join(args.uploads, "*.json")) + glob.glob(os.path.join(args.uploads, "*.lua")))
    exports, names = load_files(paths)
    if not exports:
        log("no uploads yet, nothing to post")
        return
    guild, entries = pick_guild(exports, args.guild)
    players, rules = merge_exports(entries)
    today = date.fromisoformat(args.today) if args.today else realm_today(now, rules)
    payloads = build_weekly(players, rules, today, args.top, guild, source_note(exports, names, tz))

    if args.dry_run:
        print(json.dumps(payloads, indent=2, ensure_ascii=False))
        return
    if not args.webhook:
        sys.exit("DISCORD_WEBHOOK is not set (add it as a repository secret)")
    post_discord(args.webhook, payloads)
    log(f"posted weekly results ({len(payloads)} message(s))")
    state["last_target"] = target.isoformat()
    state["posted_at"] = now.isoformat()
    save_state(args.state, state)


def cmd_daily(args):
    tz = ZoneInfo(args.tz)
    now = datetime.now(tz)
    hh, mm = args.daily_time.split(":")
    target = daily_target(now, (int(hh), int(mm)))
    sections = [x.strip().lower() for x in args.sections.split(",") if x.strip().lower() in DAILY_SECTIONS]

    try:
        with open(args.state) as f:
            state = json.load(f)
    except (OSError, ValueError):
        state = {}

    if not args.force:
        if state.get("last_target") == target.isoformat():
            log(f"already done for the {target:%a %d %b %H:%M} slot, nothing to do")
            return
        if now - target > timedelta(hours=20):
            log(f"the {target:%a %d %b %H:%M} slot is too old, skipping it")
            if not args.dry_run:
                state["last_target"] = target.isoformat()
                save_state(args.state, state)
            return

    paths = sorted(glob.glob(os.path.join(args.uploads, "*.json")) + glob.glob(os.path.join(args.uploads, "*.lua")))
    exports, names = load_files(paths)
    if not exports:
        log("no uploads yet, nothing to post")
        return
    guild, entries = pick_guild(exports, args.guild)
    players, rules = merge_exports(entries)
    if args.today:
        day = date.fromisoformat(args.today) - timedelta(days=1)
    else:
        day = realm_today(target, rules) - timedelta(days=1)
    payloads = build_daily(players, rules, day, sections or ("player",), guild,
                           source_note(exports, names, tz), args.min_players)

    if args.dry_run:
        print(json.dumps(payloads, indent=2, ensure_ascii=False) if payloads else f"quiet day ({day}): nothing to post")
        return
    if payloads:
        if not args.webhook:
            sys.exit("DISCORD_WEBHOOK is not set (add it as a repository secret)")
        post_discord(args.webhook, payloads)
        log(f"posted daily results for {day}")
    else:
        log(f"quiet day ({day}): fewer than {args.min_players} members qualified, not posting")
    state["last_target"] = target.isoformat()
    state["day"] = day.isoformat()
    state["posted"] = bool(payloads)
    save_state(args.state, state)


def save_state(path, state):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        json.dump(state, f, indent=1)
        f.write("\n")


def cmd_preview_or_post(args):
    tz = ZoneInfo(args.tz)
    exports, names = load_files(args.sv)
    if not exports:
        sys.exit("no readable files")
    guild, entries = pick_guild(exports, args.guild)
    players, rules = merge_exports(entries)
    today = date.fromisoformat(args.today) if args.today else realm_today(datetime.now(tz), rules)
    if args.daily:
        sections = [x.strip().lower() for x in args.sections.split(",") if x.strip().lower() in DAILY_SECTIONS]
        payloads = build_daily(players, rules, today - timedelta(days=1), sections or ("player",), guild,
                               source_note(exports, names, tz), args.min_players)
        if not payloads:
            print(f"quiet day ({today - timedelta(days=1)}): fewer than {args.min_players} members qualified")
            return
    else:
        payloads = build_weekly(players, rules, today, args.top, guild, source_note(exports, names, tz))
    if args.command == "preview":
        print(json.dumps(payloads, indent=2, ensure_ascii=False))
    else:
        if not args.webhook:
            sys.exit("--webhook (or DISCORD_WEBHOOK) is required")
        post_discord(args.webhook, payloads)
        print(f"Posted {len(payloads)} message(s).")


def main():
    ap = argparse.ArgumentParser(description="Guild Ranks weekly and daily Discord posts")
    sub = ap.add_subparsers(dest="command", required=True)
    w = sub.add_parser("weekly", help="post last week's results once per posting slot")
    w.add_argument("--uploads", default="uploads")
    w.add_argument("--state", default="state/weekly-post.json")
    w.add_argument("--post-day", default=os.environ.get("POST_DAY", "wed"))
    w.add_argument("--post-time", default=os.environ.get("POST_TIME", "20:00"))
    w.add_argument("--force", action="store_true", help="post now even if this slot was already posted")
    w.add_argument("--dry-run", action="store_true", help="print the messages instead of posting")
    d = sub.add_parser("daily", help="post yesterday's results once per day")
    d.add_argument("--uploads", default="uploads")
    d.add_argument("--state", default="state/daily-post.json")
    d.add_argument("--daily-time", default=os.environ.get("DAILY_TIME") or "09:00")
    d.add_argument("--force", action="store_true", help="post now even if today's slot was already done")
    d.add_argument("--dry-run", action="store_true", help="print the messages instead of posting")
    for name in ("preview", "post"):
        p = sub.add_parser(name, help=f"{name} last week's (or with --daily yesterday's) results from local files")
        p.add_argument("--sv", action="append", required=True, help="GuildRanks.lua or export .json (repeatable)")
        p.add_argument("--daily", action="store_true", help="yesterday's daily post instead of the weekly one")
    for p in sub.choices.values():
        p.add_argument("--today", help="pretend today is YYYY-MM-DD (realm date)")
        p.add_argument("--tz", default=os.environ.get("TIMEZONE", "Europe/Malta"))
        p.add_argument("--top", type=int, default=int(os.environ.get("TOP_N", "5")))
        p.add_argument("--webhook", default=os.environ.get("DISCORD_WEBHOOK"))
        p.add_argument("--guild", default=os.environ.get("GUILD") or None,
                       help='guild to post, e.g. "My Guild-Realm" (needed if uploads contain several)')
        p.add_argument("--sections", default=os.environ.get("DAILY_SECTIONS") or "player",
                       help="daily post parts, comma separated: player,top,week,spoon")
        p.add_argument("--min-players", type=int, default=int(os.environ.get("DAILY_MIN_PLAYERS") or "2"),
                       help="skip the daily post when fewer members qualified")
    args = ap.parse_args()
    if args.command == "weekly":
        cmd_weekly(args)
    elif args.command == "daily":
        cmd_daily(args)
    else:
        cmd_preview_or_post(args)


if __name__ == "__main__":
    main()
