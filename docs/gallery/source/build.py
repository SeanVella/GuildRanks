#!/usr/bin/env python3
"""Builds the CurseForge gallery images for Guild Ranks (docs/gallery/*.jpg).

From the repository root (needs texlua or lua5.1, Python 3 with Playwright, Chrome, ImageMagick):
    mkdir -p docs/gallery/source/out
    texlua docs/gallery/source/extract.lua > docs/gallery/source/out/data.json
    python3 docs/gallery/source/build.py
    python3 docs/gallery/source/render.py
    for f in docs/gallery/source/out/*.png; do convert "$f" -quality 90 "docs/gallery/$(basename "${f%.png}").jpg"; done


The leaderboard, Hall of Fame and Discord text come from the addon itself
(tests/wow.lua running `/granks demo`, see extract.lua -> data.json).
The Me tab, recap and lead cards use sample numbers in the addon's formats.
"""
import base64, html, json, re, sys
from pathlib import Path

HERE = Path(__file__).parent
D = json.loads((HERE / "out" / "data.json").read_text())
OUT = HERE / "out"
OUT.mkdir(exist_ok=True)
ICON = base64.b64encode((HERE.parent.parent / "curseforge-logo.png").read_bytes()).decode()

GUILD = "Lantern Watch"
ME = "Corvin"
CLASS = {"WARRIOR": "#C79C6E", "PRIEST": "#FFFFFF", "MAGE": "#3FC7EB", "ROGUE": "#FFF468", "HUNTER": "#AAD372",
         "DRUID": "#FF7C0A", "PALADIN": "#F48CBA", "WARLOCK": "#8788EE", "SHAMAN": "#0070DD"}
NAMES = {"Aldric": "WARRIOR", "Brina": "PRIEST", "Corvin": "MAGE", "Dalia": "ROGUE", "Eldon": "HUNTER", "Fenna": "DRUID",
         "Garrick": "PALADIN", "Hilde": "WARLOCK", "Ivo": "SHAMAN", "Jessa": "MAGE", "Korin": "WARRIOR", "Lyra": "PRIEST"}
ONLINE = {"Corvin", "Eldon", "Hilde", "Aldric", "Brina"}

TROPHY = ('<svg class="ico" viewBox="0 0 24 24"><path d="M6 3h12v3h3v2a5 5 0 0 1-5 5h-.4A5 5 0 0 1 13 15.9V18h3v3H8v-3h3v-2.1'
          'A5 5 0 0 1 8.4 13H8a5 5 0 0 1-5-5V6h3V3zm-1 5a3 3 0 0 0 1 2.2V8H5zm14 0h-1v2.2A3 3 0 0 0 19 8z" fill="#f2c94c" '
          'stroke="#7a5a10" stroke-width=".8"/></svg>')


def cname(name, extra=""):
    cls = NAMES.get(name)
    col = CLASS.get(cls, "#fff")
    return f'<span style="color:{col}">{html.escape(name)}</span>{extra}'


def wow(text):
    """WoW escape codes (|cffRRGGBB..|r, |T..|t) to HTML, with class colours for known names."""
    text = html.escape(text, quote=False)
    text = re.sub(r"\|T[^|]*Trophy[^|]*\|t", TROPHY, text)
    text = re.sub(r"\|T[^|]*\|t", "", text)
    def col(m):
        hexc, inner = m.group(1), m.group(2)
        if hexc.lower() == "ffffff" and inner in NAMES:
            return cname(inner)
        return f'<span style="color:#{hexc}">{inner}</span>'
    text = re.sub(r"\|c[0-9a-fA-F]{2}([0-9a-fA-F]{6})(.*?)\|r", col, text)
    return text


def money(s):
    """'11g 32s/h' -> coloured like the addon (gold g, silver s)."""
    s = html.escape(s)
    s = re.sub(r"(\d)g\b", r'\1<span class="cg">g</span>', s)
    s = re.sub(r"(\d)s\b", r'\1<span class="cs">s</span>', s)
    s = re.sub(r"(\d)c\b", r'\1<span class="cc">c</span>', s)
    return s


def change(c):
    if c == "":
        return ""
    if c == "new":
        return '<span style="color:#5ac8fa">new</span>'
    n = int(c)
    if n > 0:
        return f'<span style="color:#40ff40">+{n}</span>'
    if n < 0:
        return f'<span style="color:#ff5050">{n}</span>'
    return '<span style="color:#808080">=</span>'


CSS = """
@font-face { font-family: X; src: local('Inter'); }
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 1920px; height: 1080px; overflow: hidden; }
body { font-family: 'Inter', sans-serif; color: #fff; position: relative;
  background: radial-gradient(ellipse 1100px 800px at 72% 52%, #1b2c52 0%, #0f1a33 45%, #070b16 100%); }
body::before { content: ""; position: absolute; inset: 0;
  background: radial-gradient(circle 520px at 72% 50%, rgba(242,201,76,.10), transparent 70%); }
.left { position: absolute; left: 110px; top: 0; bottom: 0; width: 720px; display: flex; flex-direction: column; justify-content: center; }
.brand { display: flex; align-items: center; gap: 18px; margin-bottom: 34px; }
.brand img { width: 64px; height: 64px; border-radius: 14px; box-shadow: 0 6px 20px rgba(0,0,0,.5); }
.brand span { font: 800 26px 'Inter Display', 'Inter'; letter-spacing: .18em; color: #f2c94c; text-transform: uppercase; }
h1 { font: 900 78px/1.03 'Inter Display', 'Inter'; letter-spacing: -.02em; margin-bottom: 26px; }
h1 em { font-style: normal; color: #f2c94c; }
.sub { font: 500 30px/1.4 'Inter'; color: #c4cde0; margin-bottom: 40px; }
ul.pts { list-style: none; }
ul.pts li { font: 500 27px/1.35 'Inter'; color: #e8ecf5; padding-left: 50px; position: relative; margin-bottom: 20px; }
ul.pts li::before { content: ""; position: absolute; left: 0; top: 4px; width: 30px; height: 30px; border-radius: 50%;
  background: #f2c94c url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='M5 12.5l4.5 4.5L19 7.5' fill='none' stroke='%23182240' stroke-width='3.2' stroke-linecap='round' stroke-linejoin='round'/></svg>") center/20px no-repeat; }
.foot { position: absolute; left: 110px; bottom: 48px; font: 600 21px 'Inter'; color: #7f8aa6; letter-spacing: .02em; }
.foot b { color: #f2c94c; font-weight: 700; }
.stage { position: absolute; right: 90px; top: 50%; transform-origin: right center; }

/* ---- WoW-like window ---- */
.win { position: relative; width: 600px; background: rgba(8,8,10,.94);
  border-radius: 9px; border: 3px solid #5d5d62;
  box-shadow: inset 0 0 0 1px #1d1d20, inset 0 0 0 3px #2c2c30, 0 0 0 1px #0a0a0c, 0 30px 80px rgba(0,0,0,.75), 0 0 0 7px rgba(255,255,255,.02);
  font-family: 'Inter', sans-serif; overflow: hidden; }
.win::before { content: ""; position: absolute; inset: 0; pointer-events: none; border-radius: 6px;
  background: repeating-linear-gradient(45deg, rgba(255,255,255,.012) 0 2px, transparent 2px 5px); }
.a { position: absolute; white-space: nowrap; }
.gold { color: #ffd100; } .hl { color: #fff; } .dis { color: #8a8a8a; } .muted { color: #b9b4a8; }
.lg { font-size: 16px; font-weight: 600; } .nm { font-size: 12px; } .sm { font-size: 10.5px; }
.close { position: absolute; right: 9px; top: 8px; width: 22px; height: 22px; border-radius: 4px;
  background: linear-gradient(#8b1a12, #5a0d08); border: 1px solid #c79a32; color: #f3d48a; font: 700 13px/19px Inter; text-align: center; }
.tab { position: absolute; top: 40px; height: 24px; border-radius: 6px 6px 0 0; border: 1px solid #45403a; border-bottom: none;
  background: linear-gradient(#24221f, #141312); color: #c9b98f; font: 600 11.5px/23px Inter; text-align: center; }
.tab.on { background: linear-gradient(#4a3d18, #231d0d); color: #ffd100; border-color: #8a7330; }
.rule { position: absolute; left: 14px; right: 14px; height: 1px; background: rgba(140,120,80,.8); }
.chip { position: absolute; height: 20px; font: 500 10.5px/20px Inter; text-align: center; color: #d9d1bf; background: rgba(41,41,46,.9); }
.chip.on { background: rgba(115,92,20,.9); color: #ffd100; }
.dd { position: absolute; height: 22px; border-radius: 3px; border: 1px solid #4b4b52; background: linear-gradient(#202024, #121214);
  color: #fff; font: 500 11px/20px Inter; padding-left: 8px; }
.dd::after { content: "▾"; position: absolute; right: 6px; top: 0; color: #ffd100; font-size: 11px; }
.cb { position: absolute; font: 500 11px/18px Inter; color: #fff; padding-left: 22px; }
.cb::before { content: ""; position: absolute; left: 0; top: 1px; width: 15px; height: 15px; border: 1px solid #6b6b70; border-radius: 2px; background: #111; }
.cb.on::after { content: "✓"; position: absolute; left: 2px; top: -2px; color: #ffd100; font: 900 15px Inter; }
.btn { position: absolute; height: 22px; border-radius: 4px; border: 1px solid #a37b1d;
  background: linear-gradient(#8f1d14, #5b0f0a); color: #ffd100; font: 600 11px/20px Inter; text-align: center; }
.box { position: absolute; height: 22px; background: rgba(28,28,32,.95); border: 1px solid #3a3730; font: 500 10.5px/20px Inter; padding-left: 6px; overflow: hidden; }
.row { position: absolute; left: 18px; width: 530px; height: 20px; font-size: 12px; }
.row > * { position: absolute; top: 0; line-height: 20px; }
.bar { position: absolute; top: 7px; height: 6px; background: #292b33; }
.bar i { position: absolute; left: 0; top: 0; bottom: 0; background: #c9a326; }
.dot { display: inline-block; width: 7px; height: 7px; border-radius: 50%; margin-right: 5px; vertical-align: 1px; }
.cg { color: #ffd700; } .cs { color: #c7c7cf; } .cc { color: #eda55f; }
.ico { width: 12px; height: 12px; vertical-align: -1px; }
.tile { position: absolute; background: rgba(28,31,36,.92); }
"""


def page(left_html, stage_html, scale, foot=True):
    f = ('<div class="foot">Free addon for <b>WoW: Forever</b>  ·  CurseForge  ·  GitHub  ·  '
         'sample data shown</div>') if foot else ""
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>
<div class="left">{left_html}</div>
<div class="stage" style="transform: translateY(-50%) scale({scale})">{stage_html}</div>
{f}</body></html>"""


def left(title, sub, points):
    pts = "".join(f"<li>{p}</li>" for p in points)
    return (f'<div class="brand"><img src="data:image/png;base64,{ICON}"><span>Guild Ranks</span></div>'
            f"<h1>{title}</h1><div class=\"sub\">{sub}</div><ul class=\"pts\">{pts}</ul>")


def a(x, y, cls, text, w=None, align=None, extra=""):
    st = f"left:{x}px;top:{y}px;"
    if w:
        st += f"width:{w}px;"
    if align:
        st += f"text-align:{align};"
    return f'<div class="a {cls}" style="{st}{extra}">{text}</div>'


def window_frame(height, tab, body, subtitle=None):
    tabs = [("Ranks", 80, "list"), ("Me", 56, "me"), ("Hall of Fame", 110, "hall"), ("Members", 90, "members"), ("Settings", 90, "settings")]
    x, t = 16, ""
    for name, w, key in tabs:
        t += f'<div class="tab{" on" if key == tab else ""}" style="left:{x}px;width:{w}px">{name}</div>'
        x += w + 4
    h = [f'<div class="win" style="height:{height}px">',
         a(22, 16, "gold lg", "Guild Ranks"),
         a(122, 18.5, "nm muted", f"·&nbsp; {GUILD}"),
         a(335, 21, "dis sm", wow(D["reset"]).replace("realm time  ·  ", "realm time<br>"), w=225, align="right", extra="white-space:normal;line-height:13px;top:15px"),
         '<div class="close">✕</div>', t, '<div class="rule" style="top:64px"></div>']
    if subtitle:
        h.append(a(20, 73, "hl sm", subtitle, w=560, align="center"))
    h.append(body)
    h.append("</div>")
    return "".join(h)


# ---------------------------------------------------------------- 1. leaderboard
def ranks_view(board, metric_key, per_hour=False, rows_n=10):
    b = []
    y0 = 68
    mvp, spoon = D["mvp"], D["spoon"]
    award = f'MVP last week: {cname(mvp["name"])} ({mvp["score"]})  ·  Wooden spoon: {cname(spoon["name"])} ({spoon["score"]})'
    b.append(f'<div class="box hl" style="left:18px;top:{y0+4}px;width:556px">{TROPHY} {award}</div>')
    ch = D["challenge"]
    b.append(f'<div class="box hl" style="left:18px;top:{y0+30}px;width:275px">Challenge: most {ch["metric"]}/h  ·  {cname(ch["leader"])} leads  ·  prize {ch["prize"]}</div>')
    g = D["goal"]
    pct = max(0.02, g["pct"])
    b.append(f'<div class="box hl" style="left:299px;top:{y0+30}px;width:275px;padding:0">'
             f'<div style="position:absolute;left:3px;top:3px;bottom:3px;width:{(275-8)*pct}px;background:rgba(201,163,38,.35)"></div>'
             f'<div style="position:relative;padding-left:6px">Guild goal: {money(g["cur"])} / {money(g["target"])} Gold</div></div>')
    by = y0 + 56  # body top
    chips = [("Score", 54, "score"), ("Gold", 50, "gold"), ("XP", 40, "xp"), ("Damage", 64, "damage"), ("Quests", 60, "quests")]
    x = 18
    for name, w, key in chips:
        b.append(f'<div class="chip{" on" if key == metric_key else ""}" style="left:{x}px;top:{by+2}px;width:{w}px">{name}</div>')
        x += w + 4
    b.append(f'<div class="dd" style="left:{x+2}px;top:{by}px;width:140px;color:#ddd">More rankings</div>')
    b.append(f'<div class="cb{" on" if per_hour else ""}" style="left:482px;top:{by+2}px">Per hour</div>')
    b.append(f'<div class="dd" style="left:18px;top:{by+28}px;width:120px">This week</div>')
    b.append(f'<div class="dd" style="left:144px;top:{by+28}px;width:100px">All levels</div>')
    b.append(a(254, by + 33, "dis sm", board["desc"]))
    b.append(f'<div class="cb" style="left:482px;top:{by+29}px">Online only</div>')
    hy = by + 58
    b.append(a(18, hy, "gold sm", "#", w=28, align="right") + a(54, hy, "gold sm", "Name") + a(258, hy, "gold sm", "Lvl", w=32, align="center")
             + a(300, hy, "gold sm", board["header"], w=158, align="right") + a(462, hy, "gold sm", "+/-", w=34, align="right")
             + a(500, hy, "gold sm", "Played", w=48, align="right"))
    ry = hy + 20
    rows = board["rows"][:rows_n]
    top = rows[0]["raw"] if rows else 1
    rank_col = {1: "#ffd700", 2: "#c7c7cf", 3: "#cd7f32"}
    for i, r in enumerate(rows):
        frac = r["raw"] / 100 if metric_key == "score" else r["raw"] / top
        bg = "rgba(51,204,102,.18)" if r["name"] == ME else ("rgba(255,255,255,.04)" if (i + 1) % 2 == 0 else "transparent")
        dot = ('<span class="dot" style="background:#3ddc5a;box-shadow:0 0 4px #3ddc5a"></span>' if r["name"] in ONLINE
               else '<span class="dot" style="background:#4a4a4a"></span>')
        badge = f' {TROPHY}' + (f'<span class="hl" style="font-size:10px">x{r["mvp"]}</span>' if r["mvp"] > 1 else "") if r["mvp"] else ""
        val = money(r["value"]) if "g" in r["value"] and metric_key == "gold" else html.escape(r["value"])
        b.append(f'<div class="row" style="top:{ry + i*20}px;background:{bg}">'
                 f'<div style="left:0;width:28px;text-align:right;color:{rank_col.get(r["rank"], "#fff")}">{r["rank"]}.</div>'
                 f'<div style="left:36px;width:200px">{dot}{cname(r["name"])}{badge}</div>'
                 f'<div class="hl" style="left:240px;width:32px;text-align:center">{r["level"]}</div>'
                 f'<div class="bar" style="left:282px;width:96px"><i style="width:{96*min(1,frac):.0f}px"></i></div>'
                 f'<div class="hl" style="left:{380 if metric_key != "gold" else 360}px;width:{60 if metric_key != "gold" else 80}px;text-align:right">{val}</div>'
                 f'<div style="left:444px;width:34px;text-align:right;font-size:10.5px">{change(r["change"])}</div>'
                 f'<div class="hl" style="left:482px;width:48px;text-align:right;font-size:10.5px">{r["played"]}</div></div>')
    fy = ry + len(rows) * 20 + 22
    b.append(a(22, fy, "dis sm", f'Sample data  ·  <span class="dot" style="background:#3ddc5a"></span>{len(ONLINE)} online  ·  2 under 30 min (not ranked)'))
    by2 = fy + 26
    b.append(f'<div class="btn" style="left:{600-20-125}px;top:{by2}px;width:125px">Copy for Discord</div>')
    b.append(f'<div class="btn" style="left:{600-20-125-6-70}px;top:{by2}px;width:70px">Sync</div>')
    b.append(f'<div class="btn" style="left:{600-20-125-6-70-6-80}px;top:{by2}px;width:80px">Invite</div>')
    return window_frame(by2 + 22 + 16, "list", "".join(b))


def slide_hero():
    return page(left("See who's <em>carrying</em> your guild.",
                     "Weekly leaderboards for WoW: Forever guilds, filled in automatically while you play.",
                     ["15 rankings: gold, XP, damage, healing, quests, kills and more",
                      "A guild score and a weekly MVP",
                      "Nothing to set up: install it and your guild's data syncs in game"]),
                ranks_view(D["score"], "score"), 1.6)


def slide_fair():
    return page(left("Fair for <em>every</em> player.",
                     "Ranked per hour of play, so a two-hour evening can beat a twelve-hour weekend.",
                     ["Per hour or totals, today, this week, this month or all time",
                      "Level ranges so new players compete with each other",
                      "See who moved up and down since last week"]),
                ranks_view(D["gold"], "gold", per_hour=True), 1.6)


# ---------------------------------------------------------------- 2. Me tab
def me_view():
    b = []
    y0 = 68
    b.append(a(20, y0 + 6, "lg", cname(ME)) + a(80, y0 + 9, "gold sm", "&lt;Gold Baron&gt;") + a(160, y0 + 9, "dis sm", "level 52  ·  this week #2 of 10"))
    x = 578
    for key, text, w in reversed([("today", "Today", 50), ("week", "This week", 70), ("all", "All time", 62)]):
        x -= w
        b.append(f'<div class="chip{" on" if key == "week" else ""}" style="left:{x}px;top:{y0+6}px;width:{w}px">{text}</div>')
        x -= 4
    tiles = [("Played", "7h 11m", '<span style="color:#40ff40">+1h 05m</span>'),
             ("Gold/h", money("9g 59s"), '<span style="color:#40ff40">+14%</span> vs last week'),
             ("XP/h", "38,240", '<span style="color:#40ff40">+6%</span>'),
             ("Levels", "1.84", '<span style="color:#40ff40">+0.32</span>'),
             ("Quests", "41", '<span style="color:#ff5050">-3</span>')]
    for i, (lab, val, ch) in enumerate(tiles):
        tx = 18 + i * 112
        b.append(f'<div class="tile" style="left:{tx}px;top:{y0+32}px;width:106px;height:50px"></div>')
        b.append(a(tx + 6, y0 + 37, "dis sm", lab) + a(tx + 6, y0 + 49, "hl", val, extra="font-size:15px;font-weight:600")
                 + a(tx + 6, y0 + 68, "hl sm", ch))
    vals = [6.2, 8.9, 7.4, 10.8, 9.1, 12.4, 9.6]
    days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Today"]
    mx = max(vals)
    for i, vv in enumerate(vals):
        bx = 18 + i * 80
        h = 56 * vv / mx
        col = "#c9a326" if i == 6 else "#5c4a1a"
        b.append(f'<div style="position:absolute;left:{bx}px;top:{y0+150-h}px;width:72px;height:{h}px;background:{col};opacity:.9"></div>')
        b.append(a(bx, y0 + 152, "dis sm", days[i], w=72, align="center"))
    b.append(f'<div class="dd" style="left:16px;top:{y0+166}px;width:130px">Gold/h</div>')
    b.append(a(276, y0 + 172, "dis sm", "Today: " + money("9g 60s") + "/h", w=300, align="right"))
    L1 = 18
    b.append(a(L1 + 2, y0 + 198, "gold nm", "Goals"))
    b.append(f'<div class="btn" style="left:{L1+180}px;top:{y0+194}px;width:90px;height:18px;line-height:16px">+ Add goal</div>')
    goals = [(money("500g 0s") + " this week", money("362g 9s") + '  ·  <span style="color:#40ff40">on track</span>', .72),
             ("Reach level 55", "52.6  ·  about 11h 20m at your pace", .53),
             ("1,000 kills this week", '512  ·  <span style="color:#ffaa40">59 behind</span>', .51)]
    for i, (lab, st, f) in enumerate(goals):
        gy = y0 + 216 + i * 32
        b.append(a(L1 + 2, gy, "hl sm", lab) + a(L1 + 2, gy, "hl sm", st, w=248, align="right"))
        b.append(f'<div class="bar" style="left:{L1+2}px;top:{gy+15}px;width:250px"><i style="width:{250*f:.0f}px"></i></div>')
    b.append(a(L1 + 2, y0 + 340, "gold nm", "Personal bests"))
    bests = [("Gold/h in a day", money("12g 40s")), ("Gold in a day", money("41g 18s")), ("XP in a day", "112,450"),
             ("Levels in a day", "0.71"), ("Quests in a day", "19"), ("Kills in a day", "286"), ("Days in a row", "9")]
    for i, (lab, val) in enumerate(bests):
        yy = y0 + 358 + i * 15
        b.append(a(L1 + 2, yy, "hl sm", lab) + a(L1 + 132, yy, "hl sm", val, w=138, align="right"))
    b.append(f'<div class="btn" style="left:{L1}px;top:{y0+476}px;width:130px">Session recap</div>')
    R = 306
    b.append(a(R + 2, y0 + 198, "gold nm", "Rival: " + cname("Eldon")))
    b.append(f'<div class="dd" style="left:{R+160}px;top:{y0+194}px;width:110px">Eldon</div>')
    b.append(a(R + 140, y0 + 218, "dis sm", "You", w=60, align="right") + a(R + 205, y0 + 218, "dis sm", "Eldon", w=64, align="right"))
    h2h = [("Guild score", "70", "71", False), ("Gold/h", money("9g 59s"), money("8g 25s"), True), ("XP/h", "38.2K", "41.0K", False),
           ("Quests", "41", "37", True), ("Kills", "512", "598", False)]
    for i, (lab, mine, them, win) in enumerate(h2h):
        yy = y0 + 233 + i * 15
        mc = "#40ff40" if win else "#fff"
        tc = "#fff" if win else "#40ff40"
        b.append(a(R + 2, yy, "hl sm", lab) + a(R + 140, yy, "sm", f'<span style="color:{mc}">{mine}</span>', w=60, align="right")
                 + a(R + 205, yy, "sm", f'<span style="color:{tc}">{them}</span>', w=64, align="right"))
    b.append(a(R + 2, y0 + 312, "dis sm", "You lead 2 of 5"))
    b.append(a(R + 2, y0 + 340, "gold nm", "Titles this week"))
    titles = ["MVP", "Gold Baron", "Treasure Hunter", "Fast Learner", "Rising Star", "Heavy Hitter", "Life Saver", "Slayer",
              "Quest Machine", "Boss Hunter", "Dungeon Crawler", "Gatherer", "Artisan", "Iron Man"]
    earned = {"Gold Baron": "shown", "Heavy Hitter": "earned"}
    for i, t in enumerate(titles):
        col, row = i % 3, i // 3
        st = earned.get(t)
        bg = "rgba(115,92,20,.95)" if st == "shown" else ("rgba(40,90,50,.9)" if st == "earned" else "rgba(34,34,38,.85)")
        fc = "#ffd100" if st == "shown" else ("#fff" if st else "#77777c")
        b.append(f'<div style="position:absolute;left:{R + col*90}px;top:{y0+358+row*21}px;width:86px;height:18px;background:{bg};'
                 f'color:{fc};font:500 9.5px/18px Inter;text-align:center">{t}</div>')
    b.append(a(R + 2, y0 + 466, "dis sm", "Click one of your titles to show it to your guild."))
    return window_frame(y0 + 476 + 22 + 22, "me", "".join(b))


def slide_me():
    return page(left("Your own<br><em>stats page</em>.",
                     "The Me tab shows how your week is going, even if you never top a leaderboard.",
                     ["Your week compared with last week, plus a 7-day chart",
                      "Personal goals with your pace, and personal bests",
                      "Pick a rival and see who's ahead in each ranking"]),
                me_view(), 1.55)


# ---------------------------------------------------------------- 3. Recap
def recap_view():
    b = ['<div class="win" style="width:460px;height:376px">']
    b.append(a(22, 18, "gold lg", "Your last session") + a(258, 22, "dis sm", "Sat 22:41", w=160, align="right")
             + '<div class="close">✕</div>' + a(22, 40, "dis sm", "4h 01m played  ·  % = compared with your usual rate this week"))
    b.append(a(22, 60, "gold nm", "What you earned"))
    big = [("Gold", "+" + money("38g 52s"), money("9g 35s") + '/h  <span style="color:#40ff40">+24%</span>'),
           ("Experience", "151,880", '37,770/h  <span style="color:#40ff40">+8%</span>'),
           ("Levels", "+0.62", '<span style="color:#808080">now level 52</span>')]
    for i, (lab, val, note) in enumerate(big):
        x = 20 + i * 140
        b.append(f'<div class="tile" style="left:{x}px;top:78px;width:134px;height:54px"></div>')
        b.append(a(x + 7, 83, "dis sm", lab) + a(x + 7, 96, "hl", val, extra="font-size:16px;font-weight:600") + a(x + 7, 117, "hl", note, extra="font-size:9.5px"))
    b.append(a(22, 142, "gold nm", "What you did"))
    icons = ["📜", "⚔️", "💀", "🌿", "🔨", "🏆"]
    small = [("Quests", "14"), ("Kills", "231"), ("Deaths", "1"), ("Gathered", "38"), ("Crafted", "6"),
             ("Guild rank", '#2  <span style="color:#40ff40">+3</span>')]
    for i, (lab, val) in enumerate(small):
        col, row = i % 3, i // 3
        x, y = 20 + col * 140, 160 + row * 34
        b.append(f'<div class="tile" style="left:{x}px;top:{y}px;width:134px;height:30px"></div>')
        b.append(f'<div style="position:absolute;left:{x+5}px;top:{y+5}px;width:20px;height:20px;border:1px solid #555;background:#1a1a1d;'
                 f'font-size:12px;line-height:19px;text-align:center">{icons[i]}</div>')
        b.append(a(x + 30, y + 3, "dis sm", lab) + a(x + 30, y + 14, "hl nm", val, extra="font-weight:600"))
    b.append(a(22, 234, "gold nm", "Highlights"))
    hi = [("Gold/h in a day", money("12g 40s") + " (was " + money("11g 2s") + ")"), ("Days in a row", "9 (was 8)")]
    for i, (lab, note) in enumerate(hi):
        y = 252 + i * 36
        b.append(f'<div class="tile" style="left:20px;top:{y}px;width:414px;height:32px"></div>')
        b.append(f'<div style="position:absolute;left:26px;top:{y+6}px">{TROPHY.replace("class=\"ico\"", "style=\"width:20px;height:20px\"")}</div>')
        b.append(a(52, y + 3, "hl nm", f'New personal best: <span class="gold">{lab}</span>') + a(52, y + 17, "dis sm", note))
    b.append('<div class="btn" style="left:20px;top:336px;width:150px">Post in guild chat</div>')
    b.append('<div class="btn" style="left:360px;top:336px;width:80px">Close</div>')
    b.append("</div>")
    chat = ('<div style="margin-top:26px;width:460px;font:500 12.5px/1.4 Inter;color:#40ff40;text-shadow:0 1px 2px #000">'
            '[Guild] [Corvin]: My session: 4h 01m · +38g 52s · +0.6 levels · 14 quests · 231 kills · 2 new personal best(s) (Guild Ranks)</div>')
    return "".join(b) + chat


def slide_recap():
    return page(left("A <em>recap</em> every time you log in.",
                     "See what your last session was worth, compared with your usual.",
                     ["Gold, XP and levels per hour, against your weekly average",
                      "Quests, kills, deaths, gathering, crafting and your guild rank",
                      "New personal bests, and one click to post it in guild chat"]),
                recap_view(), 1.85)


# ---------------------------------------------------------------- 4. Lead cards
def card(kicker, title, subtitle, gold=True):
    border = "#c9a326" if gold else "#6d6d72"
    glow = "0 0 40px rgba(242,201,76,.35)," if gold else ""
    icon = TROPHY.replace('class="ico"', 'style="width:40px;height:40px' + ("" if gold else ";filter:grayscale(1) brightness(.8)") + '"')
    kc = "#ffd100" if gold else "#a0a0a5"
    return (f'<div style="position:relative;width:380px;height:84px;border-radius:8px;border:2px solid {border};'
            f'background:linear-gradient(90deg,rgba(40,32,10,.96),rgba(12,12,14,.96));box-shadow:{glow}0 18px 40px rgba(0,0,0,.6);margin-bottom:24px">'
            f'<div style="position:absolute;left:14px;top:14px;width:54px;height:54px;border:2px solid {border};border-radius:6px;'
            f'background:#141414;display:flex;align-items:center;justify-content:center">{icon}</div>'
            f'<div class="a" style="left:82px;top:14px;color:{kc};font:600 10.5px Inter;letter-spacing:.08em;text-transform:uppercase">{kicker}</div>'
            f'<div class="a" style="left:82px;top:30px;color:#fff;font:700 18px Inter">{title}</div>'
            f'<div class="a" style="left:82px;top:56px;color:#bbb;font:500 11.5px Inter">{subtitle}</div></div>')


def slide_lead():
    stage = ('<div style="width:420px">'
             + card("New leader  ·  this week", "You're #1 in Gold/h", "you passed " + cname("Hilde") + " (" + money("8g 83s") + "/h)")
             + card("New leader  ·  this week", cname("Aldric") + " took the lead in Quests", "You're #2  ·  0.8/h behind", gold=False)
             + '<div style="display:inline-block;padding:9px 16px;margin-top:4px;background:rgba(0,0,0,.85);border:2px solid #77777c;border-radius:5px;'
             'font:600 13.5px Inter;color:#ffd100">Eldon just passed you in XP/h (you\'re now #3)</div>'
             '<div style="margin-top:28px;display:flex;gap:8px;flex-wrap:wrap;width:420px">'
             + "".join(f'<span style="padding:5px 10px;border-radius:4px;font:600 12px Inter;background:{bg};color:{fc}">{t}</span>'
                       for t, bg, fc in [("Gold Baron", "rgba(115,92,20,.95)", "#ffd100"), ("Slayer", "rgba(40,90,50,.9)", "#fff"),
                                         ("Quest Machine", "rgba(34,34,38,.9)", "#ccc"), ("Iron Man", "rgba(34,34,38,.9)", "#ccc"),
                                         ("Life Saver", "rgba(34,34,38,.9)", "#ccc"), ("MVP", "rgba(34,34,38,.9)", "#ccc")])
             + '</div><div style="font:500 11px Inter;color:#8a8a8a;margin-top:10px">Weekly titles: finish #1 to earn one and show it to your guild</div></div>')
    return page(left("Take the lead. <em>Defend it.</em>",
                     "Something to chase every week, not just at the end of it.",
                     ["A card and a sound the moment you take #1 in a ranking",
                      "A heads-up when someone takes it from you",
                      "Weekly titles for every #1: Gold Baron, Slayer, Iron Man and more"]),
                stage, 1.8)


# ---------------------------------------------------------------- 5. Hall of Fame
def slide_hall():
    lines = D["hallText"].split("\n")
    out, section = [], ""
    for l in lines:
        if not l.strip():
            out.append('<div style="height:8px"></div>'); continue
        if l.startswith("|cffffd100"):
            section = l
            out.append(f'<div style="margin-bottom:2px">{wow(l)}</div>'); continue
        m = re.match(r"^  (\S.*?)\s{2,}(.*)$", l) if "Best week" in section else None
        if m:
            out.append(f'<div style="padding-left:12px"><span style="display:inline-block;width:96px;color:#ddd">{html.escape(m.group(1))}</span>{wow(m.group(2))}</div>')
        else:
            out.append(f'<div style="padding-left:12px">{wow(l.strip())}</div>')
    body = "".join(out)
    inner = f'<div class="a hl" style="left:22px;top:94px;width:556px;white-space:normal;font:500 11px/15px Inter">{body}</div>'
    weeks = D["hall"]["weeks"]
    win = window_frame(94 + (len(lines) - 4) * 15 + 4 * 8 + 34, "hall", inner, subtitle=f"Hall of Fame  ·  {weeks} weeks recorded")
    return page(left("A <em>Hall of Fame</em> for your guild.",
                     "Every week is saved, so records and rivalries last longer than one evening.",
                     ["Weekly MVP, with trophies next to their names",
                      "Best week in every ranking, and top-3 streaks",
                      "Weekly challenge with a prize, and a goal for the whole guild"]),
                win, 1.42)


# ---------------------------------------------------------------- 6. Discord
def discord_md(text):
    text = text.replace("Demo Guild (sample data)", GUILD)
    out = []
    emoji = {":trophy:": "🏆", ":spoon:": "🥄", ":dart:": "🎯"}
    for line in text.split("\n"):
        small = line.startswith("-# ")
        if small:
            line = line[3:]
        l = html.escape(line)
        for k, v in emoji.items():
            l = l.replace(k, v)
        l = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", l)
        out.append(f'<div style="{"font-size:12px;color:#949ba4" if small else ""}">{l}</div>')
    return "".join(out)


def slide_discord():
    lines = D["discord"].split("\n")
    keep = [l for l in lines if not any(l.startswith(p) for p in ("**Loot value", "**Levels", "**Bosses", "**Runs", "**Crafts", "**Gathering"))]
    msg = discord_md("\n".join(keep))
    stage = (f'<div style="width:700px;background:#313338;border-radius:10px;padding:22px 26px;box-shadow:0 30px 80px rgba(0,0,0,.7);'
             f'font:400 15px/1.55 \'Inter\';color:#dbdee1">'
             f'<div style="display:flex;gap:14px"><div style="width:42px;height:42px;border-radius:50%;background:#5865f2;flex:none;'
             f'display:flex;align-items:center;justify-content:center;font:700 18px Inter;color:#fff">C</div>'
             f'<div><div style="margin-bottom:4px"><span style="color:#3fc7eb;font-weight:600">Corvin</span>'
             f'<span style="color:#949ba4;font-size:12px;margin-left:8px">Today at 09:12</span></div>{msg}</div></div></div>')
    return page(left("Weekly results, <em>ready for Discord</em>.",
                     "One click copies a ready-made post. Paste it and your guild is talking.",
                     ["MVP, wooden spoon and the top 3 in every ranking",
                      "Challenge winner and guild goal progress",
                      "No bot, no website, no setup"]),
                stage, 1.25)


# ---------------------------------------------------------------- 7. How it works
def slide_how():
    steps = [("1", "Install", "From CurseForge, or the CurseForge app. Every guildmate who installs it shows up."),
             ("2", "Play", "Gold, XP, damage, quests and more are counted as you play. Nothing to switch on."),
             ("3", "Compare", "Open it with /granks or the minimap button. The leaderboards fill in as guildmates log in.")]
    cards = "".join(
        f'<div style="display:flex;gap:22px;align-items:flex-start;background:rgba(20,28,50,.85);border:1px solid #2c3a63;border-radius:14px;'
        f'padding:26px 30px;margin-bottom:22px;width:820px">'
        f'<div style="flex:none;width:58px;height:58px;border-radius:50%;background:#f2c94c;color:#182240;font:900 30px/58px \'Inter Display\';text-align:center">{n}</div>'
        f'<div><div style="font:800 30px \'Inter Display\';margin-bottom:6px">{t}</div><div style="font:500 21px/1.4 Inter;color:#c4cde0">{d}</div></div></div>'
        for n, t, d in steps)
    priv = ('<div style="width:820px;border-radius:14px;padding:22px 30px;background:rgba(242,201,76,.08);border:1px solid rgba(242,201,76,.35);'
            'font:500 20px/1.45 Inter;color:#e8ecf5"><b style="color:#f2c94c">Private by design.</b> Stats are shared only with your guild, '
            'inside the game. No account, no website. Hide your play time or stop sharing whenever you like.</div>')
    return page(left("Install it. Play. <em>That's it.</em>",
                     "Built for guilds: works for every member, whatever their level or class.",
                     ["Free and open source", "Guild leaders choose the rules: reset day, minimum play time, gold sources",
                      "English interface, works with any game client language"]),
                f"<div>{cards}{priv}</div>", 1.0, foot=False)


SLIDES = [("01-leaderboard", slide_hero), ("02-per-hour", slide_fair), ("03-me-tab", slide_me), ("04-session-recap", slide_recap),
          ("05-lead-cards", slide_lead), ("06-hall-of-fame", slide_hall), ("07-discord", slide_discord), ("08-how-it-works", slide_how)]

if __name__ == "__main__":
    only = sys.argv[1:]
    for name, fn in SLIDES:
        if only and not any(o in name for o in only):
            continue
        (OUT / f"{name}.html").write_text(fn())
    print("html written")
