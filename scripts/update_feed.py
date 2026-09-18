#!/usr/bin/env python3
import concurrent.futures
import datetime as dt
import json
import os
import urllib.request
from zoneinfo import ZoneInfo

BASE = "https://api.sofascore.com/api/v1"
ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer"
ESPN_LEAGUES = [
    "ita.1", "eng.1", "esp.1", "ger.1", "fra.1",
    "uefa.champions", "uefa.europa", "uefa.europa.conf",
    "usa.1", "ned.1", "por.1", "bel.1", "sco.1", "tur.1",
    "bra.1", "arg.1", "mex.1", "sau.1", "fifa.world",
]
MAX_MATCHES = 150
MAX_STATS = 60

def get_json(url, timeout=20):
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "MatchAIProFeed/1.0 (+github-actions)",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        if r.status != 200:
            raise RuntimeError(f"HTTP {r.status} for {url}")
        return json.load(r)

def num(value):
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        cleaned = value.replace("%", "").strip()
        try:
            return int(float(cleaned))
        except ValueError:
            return None
    return None

def stat_value(stats, names):
    for name in names:
        if name in stats and stats[name] is not None:
            value = num(stats[name])
            if value is not None:
                return value
    return 0

def empty_stats():
    return {
        "homeShots": 0, "awayShots": 0,
        "homeOn": 0, "awayOn": 0,
        "homeCorners": 0, "awayCorners": 0,
        "homeFouls": 0, "awayFouls": 0,
        "homeCards": 0, "awayCards": 0,
        "homeThrow": 0, "awayThrow": 0,
        "homeSaves": 0, "awaySaves": 0,
    }

def sofascore_event_to_match(event):
    home = event.get("homeTeam") or {}
    away = event.get("awayTeam") or {}
    tournament = event.get("tournament") or {}
    category = tournament.get("category") or {}
    status = event.get("status") or {}
    status_type = str(status.get("type") or "notstarted")
    timestamp = event.get("startTimestamp")
    local = dt.datetime.fromtimestamp(timestamp, tz=dt.timezone.utc).astimezone(ZoneInfo("Europe/Zurich")) if timestamp else None
    score_home = num((event.get("homeScore") or {}).get("current"))
    score_away = num((event.get("awayScore") or {}).get("current"))
    live = status_type in {"inprogress", "halftime", "extra_time", "penalties"}
    finished = status_type == "finished"
    return {
        "id": int(event.get("id") or 0),
        "home": str(home.get("name") or "Home"),
        "away": str(away.get("name") or "Away"),
        "time": local.strftime("%H:%M") if local else "--:--",
        "league": str(tournament.get("name") or category.get("name") or "Football"),
        "status": "LIVE" if live else ("FT" if finished else "NS"),
        "live": live,
        "scoreHome": score_home,
        "scoreAway": score_away,
        "stats": empty_stats(),
        "_status_type": status_type,
    }

def add_sofascore_stats(match):
    event_id = match["id"]
    try:
        data = get_json(f"{BASE}/event/{event_id}/statistics", timeout=15)
        periods = data.get("statistics") or []
        all_period = next((p for p in periods if p.get("period") == "ALL"), None)
        if all_period is None and periods:
            all_period = periods[0]
        groups = (all_period or {}).get("groups") or []
        home = {}
        away = {}
        for group in groups:
            for item in group.get("statisticsItems") or []:
                name = str(item.get("name") or "").strip().lower()
                if not name:
                    continue
                h = num(item.get("home"))
                a = num(item.get("away"))
                if h is not None:
                    home[name] = h
                if a is not None:
                    away[name] = a

        hs = stat_value(home, ["total shots", "shots"])
        a_s = stat_value(away, ["total shots", "shots"])
        hon = stat_value(home, ["shots on target", "shots on goal"])
        aon = stat_value(away, ["shots on target", "shots on goal"])
        hc = stat_value(home, ["corner kicks", "corners"])
        ac = stat_value(away, ["corner kicks", "corners"])
        hf = stat_value(home, ["fouls"])
        af = stat_value(away, ["fouls"])
        hy = stat_value(home, ["yellow cards"])
        ay = stat_value(away, ["yellow cards"])
        hr = stat_value(home, ["red cards"])
        ar = stat_value(away, ["red cards"])
        ht = stat_value(home, ["throw-ins", "throw ins"])
        at = stat_value(away, ["throw-ins", "throw ins"])
        hv = stat_value(home, ["goalkeeper saves", "saves"])
        av = stat_value(away, ["goalkeeper saves", "saves"])
        match["stats"] = {
            "homeShots": hs, "awayShots": a_s,
            "homeOn": hon, "awayOn": aon,
            "homeCorners": hc, "awayCorners": ac,
            "homeFouls": hf, "awayFouls": af,
            "homeCards": hy + hr, "awayCards": ay + ar,
            "homeThrow": ht, "awayThrow": at,
            "homeSaves": hv, "awaySaves": av,
        }
    except Exception:
        pass
    match.pop("_status_type", None)
    return match

def fetch_sofascore(date_str):
    data = get_json(f"{BASE}/sport/football/scheduled-events/{date_str}")
    events = data.get("events") or []
    matches = [
        sofascore_event_to_match(e)
        for e in events
        if isinstance(e, dict) and isinstance(e.get("homeTeam"), dict) and isinstance(e.get("awayTeam"), dict)
    ]
    matches = [m for m in matches if m["id"]]
    matches.sort(key=lambda m: (not m["live"], m["time"]))
    matches = matches[:MAX_MATCHES]

    stat_targets = [m for m in matches if m.get("_status_type") in {"inprogress", "halftime", "extra_time", "penalties", "finished"}][:MAX_STATS]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(add_sofascore_stats, stat_targets))
    for m in matches:
        m.pop("_status_type", None)
    return matches

def espn_event_to_match(event):
    competitions = event.get("competitions") or []
    if not competitions:
        return None
    comp = competitions[0]
    competitors = comp.get("competitors") or []
    home = next((x for x in competitors if x.get("homeAway") == "home"), None)
    away = next((x for x in competitors if x.get("homeAway") == "away"), None)
    if not home or not away:
        return None
    home_team = home.get("team") or {}
    away_team = away.get("team") or {}
    status = comp.get("status") or {}
    status_type = status.get("type") or {}
    state = str(status_type.get("state") or "")
    when = event.get("date")
    local = dt.datetime.fromisoformat(when.replace("Z", "+00:00")).astimezone(ZoneInfo("Europe/Zurich")) if when else None
    return {
        "id": int(str(event.get("id") or "0").split("-")[0] or 0),
        "home": str(home_team.get("displayName") or home_team.get("name") or "Home"),
        "away": str(away_team.get("displayName") or away_team.get("name") or "Away"),
        "time": local.strftime("%H:%M") if local else "--:--",
        "league": str((event.get("league") or {}).get("name") or "Football"),
        "status": "LIVE" if state == "in" else ("FT" if state == "post" else "NS"),
        "live": state == "in",
        "scoreHome": num(home.get("score")),
        "scoreAway": num(away.get("score")),
        "stats": empty_stats(),
    }

def fetch_espn(date_str):
    compact = date_str.replace("-", "")
    all_matches = []
    for league in ESPN_LEAGUES:
        try:
            data = get_json(f"{ESPN_BASE}/{league}/scoreboard?dates={compact}", timeout=15)
        except Exception:
            continue
        for event in data.get("events") or []:
            match = espn_event_to_match(event)
            if match and match["id"]:
                all_matches.append(match)
    unique = {}
    for m in all_matches:
        key = f'{m["home"]}|{m["away"]}|{m["time"]}'
        unique[key] = m
    result = list(unique.values())
    result.sort(key=lambda m: (not m["live"], m["time"]))
    return result[:MAX_MATCHES]

def main():
    today = dt.datetime.now(ZoneInfo("Europe/Zurich")).date()
    date_str = today.isoformat()
    try:
        matches = fetch_sofascore(date_str)
        provider = "SofaScore"
    except Exception as first_error:
        matches = fetch_espn(date_str)
        provider = "ESPN"
        if not matches:
            raise RuntimeError(f"SofaScore failed and ESPN returned no matches: {first_error}")

    payload = {
        "date": date_str,
        "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "provider": provider,
        "matches": matches,
    }
    os.makedirs("data", exist_ok=True)
    with open("data/today.json", "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(f"Feed updated: provider={provider} matches={len(matches)} date={date_str}")

if __name__ == "__main__":
    main()
