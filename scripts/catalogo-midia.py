#!/usr/bin/env python3
"""Catalogo de midia do servidor Bia — gera relatorio Markdown no vault.
AniList: busca por nome (sem IDs hardcoded, evita resultados errados).
Multi-temporada: soma os eps das temporadas buscadas individualmente.
"""
import os, math, time, requests
from pathlib import Path
from datetime import datetime

JELLYFIN   = Path("/mnt/Se0/10-Mídias(Jellyfin)")
ESTUDOS    = Path("/mnt/Se0/20-Estudos/Estudos")
MW_DIR     = Path("/mnt/Se0/20-Estudos/Método_MW_3.0-_Manutenção_de_Computadores-MIGUEL WILBERT")
VAULT_OUT  = Path("/DATA/AppData/big-bear-syncthing/data/obsidian/Second Brain/10.Projects/Locadora em Casa")
VIDEO_EXTS = {".mkv", ".mp4", ".avi", ".mov", ".m4v", ".wmv"}
VAULT_OUT.mkdir(parents=True, exist_ok=True)

ANILIST_URL = "https://graphql.anilist.co"
Q_SEARCH = """
query ($search: String) {
  Media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
    id title { romaji english } episodes status nextAiringEpisode { episode } format
  }
}"""

_cache: dict[str, dict | None] = {}

def query(search: str) -> dict | None:
    if search in _cache:
        return _cache[search]
    for _ in range(3):
        try:
            r = requests.post(ANILIST_URL, json={"query": Q_SEARCH, "variables": {"search": search}}, timeout=15)
            if r.status_code == 429:
                print("  rate-limit 65s..."); time.sleep(65); continue
            r.raise_for_status()
            result = r.json().get("data", {}).get("Media")
            _cache[search] = result
            return result
        except Exception as e:
            print(f"  err: {e}"); time.sleep(3)
    _cache[search] = None
    return None

def eps_from(m: dict | None) -> int:
    if m is None: return 0
    if m.get("nextAiringEpisode"): return m["nextAiringEpisode"]["episode"] - 1
    return m.get("episodes") or 0

def count_videos(p: Path) -> int:
    return sum(1 for f in p.rglob("*") if f.is_file() and f.suffix.lower() in VIDEO_EXTS)

def dir_size_gb(p: Path) -> float:
    t = 0
    for r, _, files in os.walk(p):
        for f in files:
            try: t += os.path.getsize(os.path.join(r, f))
            except: pass
    return t / 1024**3

def discs(gb, cap): return math.ceil(gb / cap) if gb > 0 else 0

# ── Definição dos animes ──────────────────────────────────────────────────────
# (pastas_locais, label_exibição, [(search_anilist, desc_temporada), ...])
# search=None → sem API (cartoon ocidental, pasta vazia, avulsos)
ONE_PIECE_ARCS = [
    "One Pace [1-7] Romance Dawn [1080p]",
    *[f"One Piece EX - {i} {n}" for i, n in [
        (1,"East Blue"),(2,"Baroque Works"),(3,"Skypiea"),
        (4,"Water 7 ~ CP9"),(5,"Thriller Bark"),(6,"Arquipélago Sabaody"),
        (7,"Impel Down"),(8,"Marineford"),(9,"Pós Guerra"),
        (10,"Ilha dos Tritões"),(11,"Punk Hazard"),(12,"Dressrosa"),
        (13,"Zou"),(14,"Whole Cake"),(15,"Reverie-Wano"),(16,"Egghead"),
    ]],
]

DEFS = [
    # pastas,                     label,                       [(search, desc), ...]
    (["Anime"],                   "Avulsos (misc)",            []),
    (["Pokemon"],                 "Pokémon",                   []),  # pasta vazia
    (["Avatar - The Last Airbender"], "Avatar: The Last Airbender", []),  # western, sem AniList
    (["Boku no Hero Academia (2016)"], "My Hero Academia", [
        ("My Hero Academia", "S1"),
        ("My Hero Academia Season 2", "S2"),
        ("My Hero Academia Season 3", "S3"),
        ("My Hero Academia Season 4", "S4"),
        ("My Hero Academia Season 5", "S5"),
        ("My Hero Academia Season 6", "S6"),
        ("My Hero Academia Season 7", "S7"),
    ]),
    (["Chuunibyou demo Koi ga Shitai"], "Chuunibyou demo Koi ga Shitai", [
        ("Chuunibyou demo Koi ga Shitai", "S1"),
        ("Chuunibyou demo Koi ga Shitai Ren", "S2"),
    ]),
    (["Dandadan"],                "DAN DA DAN",                [("Dandadan", "S1")]),
    (["Jujutsu Kaisen (2020)"],   "Jujutsu Kaisen",            [
        ("Jujutsu Kaisen", "S1"),
        ("Jujutsu Kaisen Season 2", "S2"),
    ]),
    (["Kaoru Hana wa Rin to Saku"], "Kaoru Hana wa Rin to Saku", [("Kaoru Hana wa Rin to Saku", "S1")]),
    (["Kijin Gentoushou"],        "Sword of the Demon Hunter", [("Kijin Gentoushou", "S1")]),
    (["Kimetsu no Yaiba (2019)"], "Kimetsu no Yaiba",          [
        ("Kimetsu no Yaiba", "S1"),
        ("Kimetsu no Yaiba Mugen Train Arc", "S2a Mugen"),
        ("Kimetsu no Yaiba Entertainment District Arc", "S2b ED Arc"),
        ("Kimetsu no Yaiba Swordsmith Village Arc", "S3"),
        ("Kimetsu no Yaiba Hashira Training Arc", "S4"),
    ]),
    (["Kimini no Todoke"],        "Kimi ni Todoke",            [
        ("Kimi ni Todoke", "S1"),
        ("Kimi ni Todoke 2nd Season", "S2"),
        ("Kimi ni Todoke 3rd Season", "S3"),
    ]),
    (["Kizumonogatari"],          "Kizumonogatari",            [
        ("Kizumonogatari Tekketsu-hen", "Parte 1"),
        ("Kizumonogatari Nekketsu-hen", "Parte 2"),
        ("Kizumonogatari Reiketsu-hen", "Parte 3"),
    ]),
    (["Kuroko no Basket"],        "Kuroko no Basket",          [
        ("Kuroko no Basket", "S1"),
        ("Kuroko no Basket 2nd Season", "S2"),
        ("Kuroko no Basket 3rd Season", "S3"),
    ]),
    (["Lupin III"],               "Lupin III Part 6",          [("Lupin III Part 6", "Part 6")]),
    (["Mashle (2023)"],           "MASHLE",                    [
        ("Mashle Magic and Muscles", "S1"),
        ("Mashle Magic and Muscles Season 2", "S2"),
    ]),
    (["Monogatari Series - Off & Monster Season"], "Monogatari Off & Monster Season",
                                                              [("Monogatari Series Off Monster Season", "S1")]),
    (["Naruto Shippuden"],        "Naruto: Shippuden",         [("Naruto Shippuden", "completo")]),
    (ONE_PIECE_ARCS,              "One Piece",                 [("One Piece", "original")]),
    (["Seishun Buta Yarou wa Bunny Girl Senpai no Yume wo Minai (2018)"],
                                  "Rascal Does Not Dream of Bunny Girl Senpai",
                                                              [("Seishun Buta Yarou wa Bunny Girl Senpai no Yume wo Minai", "S1")]),
    (["Shingeki no Kyojin 1aTemp"], "Attack on Titan",         [
        ("Attack on Titan", "S1"),
        ("Attack on Titan Season 2", "S2"),
        ("Attack on Titan Season 3", "S3"),
        ("Attack on Titan Season 3 Part 2", "S3p2"),
        ("Attack on Titan Final Season", "S4"),
        ("Attack on Titan Final Season Part 2", "S4p2"),
        ("Attack on Titan Final Season Part 3", "S4p3"),
    ]),
    (["Solo Leveling"],           "Solo Leveling",             [
        ("Solo Leveling", "S1"),
        ("Solo Leveling Season 2", "S2"),
    ]),
    (["Sousou no Frieren"],       "Frieren: Beyond Journey's End", [("Sousou no Frieren", "S1")]),
    (["Spy x Family (2022)"],     "SPY×FAMILY",                [
        ("Spy x Family", "S1"),
        ("Spy x Family Part 2", "S1p2"),
        ("Spy x Family Season 2", "S2"),
    ]),
    (["Tengen Toppa Gurren Lagann"], "Gurren Lagann",          [("Tengen Toppa Gurren Lagann", "completo")]),
    (["Yuusha-kei ni Shosu"],     "Sentenced to Be a Hero",    [("Yuusha-kei ni Shosu", "S1")]),
    (["Zom 100 (2023)"],          "Zom 100",                   [("Zom 100 Bucket List of the Dead", "S1")]),
]

# ── 1. Filmes ─────────────────────────────────────────────────────────────────
print("=== Filmes ===")
filmes = sorted(p.name for p in (JELLYFIN / "Filmes").iterdir())
print(f"  {len(filmes)} filmes")

# ── 2. Séries ─────────────────────────────────────────────────────────────────
print("=== Séries ===")
series_data = []
for p in sorted((JELLYFIN / "Séries").iterdir()):
    if p.is_dir():
        series_data.append({"nome": p.name, "eps": count_videos(p)})

# ── 3. Animes + AniList ───────────────────────────────────────────────────────
print("=== Animes + AniList ===")
ANIMES_BASE = JELLYFIN / "Animes"
anime_results = []

for (pastas, label, al_list) in DEFS:
    # Contar local
    eps_local = sum(count_videos(ANIMES_BASE / p) for p in pastas if (ANIMES_BASE / p).is_dir())

    # Consultar AniList
    eps_total = 0
    releasing = False
    details = []
    api_ok = len(al_list) > 0

    for (search, desc) in al_list:
        time.sleep(0.9)
        print(f"  [{label}] {search!r} ...", end=" ", flush=True)
        m = query(search)
        e = eps_from(m)
        st = m["status"] if m else "ERR"
        title = (m["title"]["english"] or m["title"]["romaji"]) if m else "?"
        print(f"→ {title} ({e} eps, {st})")
        eps_total += e
        details.append(f"{desc}: {e}")
        if m and m["status"] in ("RELEASING", "NOT_YET_RELEASED"):
            releasing = True

    faltam = None if not api_ok else max(0, eps_total - eps_local)

    anime_results.append({
        "label": label,
        "eps_local": eps_local,
        "eps_total": eps_total if api_ok else None,
        "faltam": faltam,
        "releasing": releasing,
        "details": " | ".join(details),
        "api_ok": api_ok,
    })
    status = f"local={eps_local}, total={eps_total if api_ok else '—'}, faltam={faltam}"
    print(f"  ✓ {label}: {status}")

# ── 4. Cursos ─────────────────────────────────────────────────────────────────
print("=== Cursos ===")
cursos = []
for p in [MW_DIR] + sorted(ESTUDOS.iterdir()):
    p = Path(p)
    if not p.is_dir() or p.name == "Programas":
        continue
    gb = dir_size_gb(p)
    cursos.append({"nome": p.name, "gb": gb,
                   "dvd_sl": discs(gb,4.7), "dvd_dl": discs(gb,8.5),
                   "bd25": discs(gb,25), "bd50": discs(gb,50)})
    print(f"  {p.name}: {gb:.1f} GB")
total_gb = sum(c["gb"] for c in cursos)

# ── 5. Markdown ───────────────────────────────────────────────────────────────
hoje = datetime.now().strftime("%Y-%m-%d")
L = []

def h(txt): L.extend(["", txt, ""])
def row(*cols): L.append("| " + " | ".join(str(c) for c in cols) + " |")
def hr(*cols): L.append("|" + "|".join("---" for _ in cols) + "|")

L += ["---","owner: Claude",f"created: {hoje}","reviewed: false",
      "status: progress","tags: [dvd, midia, catalogo]","type: note",
      "permissions:","  read: [all]","  write: [Werus, Claude]","---","",
      f"# Catálogo de Mídia — Servidor Bia ({hoje})","",
      "> Gerado por `scripts/catalogo-midia.py` (AniList via busca por nome).",
      "> Filmes/Séries: comparação TMDB pendente (API key necessária).",""]

# Filmes
L += [f"## Filmes — {len(filmes)} títulos",""]
L.append("| # | Título |"); L.append("|---|---|")
for i, f in enumerate(filmes, 1):
    L.append(f"| {i} | {f} |")

# Séries
h("## Séries")
row("Série", "Episódios"); hr("x","x")
for s in series_data:
    row(s["nome"], s["eps"])

# Animes — incompletos
incompletos = [a for a in anime_results if a["faltam"] and a["faltam"] > 0]
completos   = [a for a in anime_results if a["faltam"] == 0 and a["api_ok"]]
sem_api     = [a for a in anime_results if not a["api_ok"]]

h(f"## Animes — {len(anime_results)} séries")
L.append(f"✅ **{len(completos)} completas** · ⚠️ **{len(incompletos)} incompletas** · — {len(sem_api)} sem API")

h("### ⚠️ Incompletos (prioridade de download)")
row("Anime","Eps local","Eps total","**Faltam**","Status","Detalhe por temporada")
hr(*["x"]*6)
for a in sorted(incompletos, key=lambda x: -x["faltam"]):
    st = "🔴 AIRING" if a["releasing"] else "FINISHED"
    row(a["label"], a["eps_local"], a["eps_total"], f"**{a['faltam']}**", st, a["details"])

h("### ✅ Completos")
row("Anime","Eps","Temporadas verificadas"); hr("x","x","x")
for a in sorted(completos, key=lambda x: x["label"]):
    row(a["label"], a["eps_local"], a["details"] or "—")

if sem_api:
    h("### — Sem comparação API")
    row("Anime","Eps local","Motivo"); hr("x","x","x")
    for a in sem_api:
        motivo = "pasta vazia" if a["eps_local"]==0 else "cartoon ocidental / sem AniList"
        row(a["label"], a["eps_local"], motivo)

# Cursos
h("## Cursos — Cálculo de Mídia Física")
L.append(f"**Total: {total_gb:.1f} GB**  |  {len(cursos)} cursos")
L.append("")
row("Curso","GB","DVD SL (4,7)","DVD DL (8,5)","BD-25","BD-50"); hr(*["x"]*6)
for c in sorted(cursos, key=lambda x: -x["gb"]):
    row(c["nome"], f"{c['gb']:.1f}", c["dvd_sl"], c["dvd_dl"], c["bd25"], c["bd50"])
row("**TOTAL**", f"**{total_gb:.1f}**",
    f"**{discs(total_gb,4.7)}**", f"**{discs(total_gb,8.5)}**",
    f"**{discs(total_gb,25)}**", f"**{discs(total_gb,50)}**")

h("### Recomendação por curso")
for c in sorted(cursos, key=lambda x: -x["gb"]):
    gb = c["gb"]
    if gb > 50:    rec = f"BD-50 × {c['bd50']}"
    elif gb > 25:  rec = f"BD-25 × {c['bd25']}  (ou BD-50 × {c['bd50']})"
    elif gb > 8.5: rec = f"BD-25 × {c['bd25']}"
    elif gb > 4.7: rec = f"DVD DL × {c['dvd_dl']}  (ou BD-25 × {c['bd25']})"
    else:          rec = f"DVD SL × {c['dvd_sl']}"
    L.append(f"- **{c['nome']}** ({gb:.1f} GB) → {rec}")

L += ["","---","## Notas","",
    "- **One Piece:** total inclui todos os arcos EX + One Pace. Eps lançados até a data de geração.",
    "- **Spy×Family:** S1p2 = Season 1 Part 2 (13 eps separados no AniList como entrada distinta).",
    "- **Kimetsu no Yaiba:** S2 dividida em Mugen Train Arc + Entertainment District Arc no AniList.",
    "- **Attack on Titan:** S4 fragmentada em 3 partes no AniList — total acumulado.",
    "- **Avatar / Pokémon:** sem base de dados (ocidental/pasta vazia).",
    "- **Filmes:** comparação TMDB pendente.",
    f"- Gerado em {hoje} — rodar o script novamente para atualizar.",
]

out = VAULT_OUT / f"Catálogo de Mídia ({hoje}).md"
out.write_text("\n".join(L), encoding="utf-8")
print(f"\n✅ {out}")
print(f"Filmes: {len(filmes)} | Animes: {len(anime_results)} | Cursos: {len(cursos)}")
