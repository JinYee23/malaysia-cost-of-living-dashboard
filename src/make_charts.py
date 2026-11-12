"""Draw the README charts from the Q1-Q4 analysis files.

Each chart runs the matching sql/0X_*.sql file itself, so the charts always use exactly
the same logic as the analysis. Titles are built from the results, so they stay correct
when the data is refreshed. PNGs are saved to outputs/charts/.

Colours follow one accessible system: blue for a single series, and a blue <-> red
diverging pair with a grey midpoint for values above or below zero
(red = higher prices, blue = lower prices).
"""

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
import psycopg
import seaborn as sns
from dotenv import load_dotenv
from matplotlib.colors import LinearSegmentedColormap

PROJECT_DIR = Path(__file__).resolve().parent.parent
SQL_DIR = PROJECT_DIR / "sql"
CHART_DIR = PROJECT_DIR / "outputs" / "charts"

# Colours (validated reference palette)
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_SECONDARY = "#52514e"
INK_MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"
BLUE = "#2a78d6"      # single series; "lower price" pole
RED = "#e34948"       # "higher price" pole
NEUTRAL = "#f0efec"   # diverging midpoint
DIVERGING = LinearSegmentedColormap.from_list("blue_grey_red", ["#1c5cab", BLUE, NEUTRAL, RED, "#b3302f"])

SOURCE = "Source: DOSM open data (CPI, PriceCatcher)."

# Short English labels for long names
DIVISION_SHORT = {
    "01": "Food & bev.", "02": "Alcohol & tobacco", "03": "Clothing", "04": "Housing & utilities",
    "05": "Furnishings", "06": "Health", "07": "Transport", "08": "Info & comms",
    "09": "Recreation", "10": "Education", "11": "Restaurants & hotels", "12": "Insurance & finance",
    "13": "Personal care & misc.",
}
PREMISE_ENGLISH = {
    "Hypermarket": "Hypermarket",
    "Pasar Raya / Supermarket": "Supermarket",
    "Pasar Mini": "Mini market",
    "Kedai Runcit": "Sundry shop (kedai runcit)",
    "Pasar Basah": "Wet market (pasar basah)",
}


def run_sql_file(cur, name):
    """Run every statement in sql/<name> and return each query result as a DataFrame."""
    cur.execute((SQL_DIR / name).read_text(encoding="utf-8"))
    results = []
    while True:
        if cur.description:  # statements like CREATE VIEW return no rows
            columns = [col.name for col in cur.description]
            results.append(pd.DataFrame(cur.fetchall(), columns=columns))
        if not cur.nextset():
            return results


def query(cur, sql):
    cur.execute(sql)
    return pd.DataFrame(cur.fetchall(), columns=[col.name for col in cur.description])


def style_axes(ax, value_axis="x"):
    """Recessive axes: hairline grid on the value axis only, no box."""
    ax.set_facecolor(SURFACE)
    for side in ("top", "right", "left", "bottom"):
        ax.spines[side].set_visible(False)
    ax.tick_params(colors=INK_SECONDARY, length=0, labelsize=9)
    ax.grid(axis=value_axis, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def titles(fig, title, subtitle, note):
    fig.patch.set_facecolor(SURFACE)
    fig.text(0.02, 0.975, title, fontsize=14, fontweight="bold", color=INK, va="top")
    fig.text(0.02, 0.925, subtitle, fontsize=10, color=INK_SECONDARY, va="top")
    fig.text(0.02, 0.015, f"{note} {SOURCE}".strip(), fontsize=8, color=INK_MUTED, va="bottom", wrap=True)


def save(fig, name):
    path = CHART_DIR / name
    fig.savefig(path, dpi=200, facecolor=SURFACE)
    plt.close(fig)
    print(f"Saved {path.relative_to(PROJECT_DIR)}")


def pct_label(value):
    """'+3.0%' / '-1.9%', and plain '0.0%' so a zero never looks like a rise."""
    return "0.0%" if round(value, 1) == 0 else f"{value:+.1f}%"


def shorten(text, limit=36):
    """Shorten long item names at a word boundary, marking the cut with an ellipsis."""
    if len(text) <= limit:
        return text
    return text[:limit].rsplit(" ", 1)[0].rstrip(" (,") + "…"


def month_label(value):
    return pd.Timestamp(value).strftime("%b %Y")


def chart_state_inflation(states):
    """Q1a: states ranked by overall year-on-year inflation in the latest month."""
    df = states.sort_values("yoy_pct").astype({"yoy_pct": float})
    month = pd.Timestamp(df["date"].iloc[0]).strftime("%b %Y")
    top = df[df["yoy_pct"] == df["yoy_pct"].max()]["state"].tolist()
    low = df[df["yoy_pct"] == df["yoy_pct"].min()]["state"].tolist()

    fig, ax = plt.subplots(figsize=(9, 7))
    fig.subplots_adjust(left=0.2, right=0.95, top=0.84, bottom=0.08)
    ax.barh(df["state"], df["yoy_pct"], color=BLUE, height=0.65)
    for y, value in enumerate(df["yoy_pct"]):
        ax.text(value + 0.03, y, f"{value:.1f}%", va="center", fontsize=9, color=INK_SECONDARY)
    style_axes(ax, "x")
    ax.set_xlabel("Year-on-year CPI inflation (%)", color=INK_SECONDARY, fontsize=9)
    ax.tick_params(axis="y", colors=INK, labelsize=10)
    titles(
        fig,
        f"{' and '.join(top)} had the highest inflation; {' and '.join(low)} the lowest",
        f"Overall CPI, {month} vs a year earlier, by state",
        "Year-on-year % change in each state's overall CPI index.",
    )
    save(fig, "q1_state_inflation.png")


def chart_category_heatmap(cur, states):
    """Q1b: year-on-year inflation for every state and category in the latest month."""
    df = query(cur, """
        SELECT state, division, yoy_pct
        FROM cpi_yoy
        WHERE division <> 'overall' AND date = (SELECT max(date) FROM cpi_yoy)
    """)
    month = pd.Timestamp(states["date"].iloc[0]).strftime("%b %Y")
    grid = df.astype({"yoy_pct": float}).pivot(index="state", columns="division", values="yoy_pct")
    grid = grid.loc[states.sort_values("yoy_pct", ascending=False)["state"]]  # rows by overall inflation
    grid.columns = [DIVISION_SHORT[c] for c in grid.columns]

    limit = 6  # colour scale is capped at +/-6% so typical differences stay visible
    fig, ax = plt.subplots(figsize=(12, 7.5))
    fig.subplots_adjust(left=0.15, right=0.98, top=0.86, bottom=0.2)
    sns.heatmap(
        grid, ax=ax, cmap=DIVERGING, center=0, vmin=-limit, vmax=limit,
        linewidths=2, linecolor=SURFACE,
        cbar_kws={"label": "Year-on-year %", "shrink": 0.7, "extend": "both"},
    )
    # Label only the notable cells (4% or more either way), not every cell
    for y, state in enumerate(grid.index):
        for x, col in enumerate(grid.columns):
            value = grid.loc[state, col]
            if abs(value) >= 4:
                ax.text(x + 0.5, y + 0.5, f"{value:.0f}", ha="center", va="center",
                        fontsize=8, color="#ffffff" if abs(value) >= limit * 0.8 else INK)
    ax.set_xlabel("")
    ax.set_ylabel("")
    ax.tick_params(colors=INK, length=0, labelsize=9)
    plt.setp(ax.get_xticklabels(), rotation=40, ha="right")
    titles(
        fig,
        "Which price categories rose fastest in each state",
        f"Year-on-year CPI inflation by category, {month}. States ordered by overall inflation.",
        "Cells of 4% or more are labelled; colours are capped at ±6%. Without CPI weights, this "
        "shows which categories rose fastest, not how much each contributed.",
    )
    save(fig, "q1_category_heatmap.png")


def chart_item_changes(risers, fallers, first_month, last_month):
    """Q2: top 10 risers and fallers, as bars left and right of zero."""
    df = pd.concat([risers, fallers]).drop_duplicates("item")
    df = df.astype({"median_change_pct": float}).sort_values("median_change_pct")
    df["label"] = df["item"].str.title().map(shorten) + " (" + df["unit"] + ")"
    colours = [RED if v > 0 else BLUE for v in df["median_change_pct"]]

    fig, ax = plt.subplots(figsize=(10, 9))
    fig.subplots_adjust(left=0.38, right=0.93, top=0.87, bottom=0.08)
    ax.barh(df["label"], df["median_change_pct"], color=colours, height=0.65)
    ax.axvline(0, color=AXIS, linewidth=1)
    for y, value in enumerate(df["median_change_pct"]):
        offset = 1 if value > 0 else -1
        ax.text(value + offset, y, pct_label(value), va="center", fontsize=8.5, color=INK_SECONDARY,
                ha="left" if value > 0 else "right")
    style_axes(ax, "x")
    ax.set_xlim(df["median_change_pct"].min() - 12, df["median_change_pct"].max() + 12)
    ax.set_xlabel("Median price change at matched premises (%)", color=INK_SECONDARY, fontsize=9)
    ax.tick_params(axis="y", colors=INK, labelsize=9)
    top = df.iloc[-1]
    titles(
        fig,
        f"{top['item'].title()} rose most, up {top['median_change_pct']:.0f}%",
        f"Top 10 price rises (red) and falls (blue), {month_label(first_month)} vs {month_label(last_month)}",
        "Only premises that priced an item in both months are compared; items need at least 30 such premises.",
    )
    save(fig, "q2_item_price_changes.png")


def chart_premise_types(types):
    """Q3: each premise type's typical price vs the local median for the same item."""
    df = types.astype({"median_pct_vs_local": float}).sort_values("median_pct_vs_local")
    df["label"] = df["premise_type"].map(PREMISE_ENGLISH)
    colours = [RED if v > 0 else BLUE if v < 0 else NEUTRAL for v in df["median_pct_vs_local"]]

    fig, ax = plt.subplots(figsize=(9, 5))
    fig.subplots_adjust(left=0.3, right=0.93, top=0.8, bottom=0.14)
    ax.barh(df["label"], df["median_pct_vs_local"], color=colours, height=0.6,
            edgecolor=[AXIS if c == NEUTRAL else c for c in colours])
    ax.axvline(0, color=AXIS, linewidth=1)
    for y, value in enumerate(df["median_pct_vs_local"]):
        ax.text(value + (0.15 if value >= 0 else -0.15), y, pct_label(value), va="center", fontsize=9,
                color=INK_SECONDARY, ha="left" if value >= 0 else "right")
    style_axes(ax, "x")
    span = df["median_pct_vs_local"].abs().max() + 1.5
    ax.set_xlim(-span, span)
    ax.set_xlabel("Typical price vs local median for the same item (%)", color=INK_SECONDARY, fontsize=9)
    ax.tick_params(axis="y", colors=INK, labelsize=10)
    cheapest = df.iloc[0]["label"]
    dearest = df.iloc[-1]["label"].split(" (")[0]
    titles(
        fig,
        f"{cheapest}s are cheapest and {dearest.lower()}s dearest for the same item",
        "Median % difference from the local median, comparing the same item within the same state",
        "Each premise type needs at least 5 premises in an item-state comparison.",
    )
    save(fig, "q3_premise_type_prices.png")


def chart_basket(change, first_month, last_month):
    """Q4: basket cost per state in the first and last month (dumbbell)."""
    df = change.astype({"first_month_cost_rm": float, "last_month_cost_rm": float})
    df = df.sort_values("last_month_cost_rm")
    y = range(len(df))

    fig, ax = plt.subplots(figsize=(9, 7))
    fig.subplots_adjust(left=0.2, right=0.93, top=0.84, bottom=0.1)
    ax.hlines(y, df["first_month_cost_rm"], df["last_month_cost_rm"], color=AXIS, linewidth=2)
    ax.scatter(df["first_month_cost_rm"], y, s=60, color=INK_MUTED, label=month_label(first_month), zorder=3,
               edgecolor=SURFACE, linewidth=1.5)
    ax.scatter(df["last_month_cost_rm"], y, s=60, color=BLUE, label=month_label(last_month), zorder=3,
               edgecolor=SURFACE, linewidth=1.5)
    for i, (_, row) in enumerate(df.iterrows()):
        ax.text(max(row["first_month_cost_rm"], row["last_month_cost_rm"]) + 0.4, i,
                f"RM {row['last_month_cost_rm']:.2f}", va="center", fontsize=8.5, color=INK_SECONDARY)
    ax.set_yticks(list(y), df["state"])
    style_axes(ax, "x")
    ax.set_xlim(df[["first_month_cost_rm", "last_month_cost_rm"]].min().min() - 1,
                df[["first_month_cost_rm", "last_month_cost_rm"]].max().max() + 3)
    ax.set_xlabel("Cost of the 10-item basket (RM)", color=INK_SECONDARY, fontsize=9)
    ax.tick_params(axis="y", colors=INK, labelsize=10)
    ax.legend(loc="lower right", frameon=False, fontsize=9, labelcolor=INK_SECONDARY)
    priciest, cheapest = df.iloc[-1], df.iloc[0]
    gap = priciest["last_month_cost_rm"] - cheapest["last_month_cost_rm"]
    titles(
        fig,
        f"In {month_label(last_month)}, the same basket cost RM {gap:.2f} more in {priciest['state']} "
        f"than in {cheapest['state']}",
        "One unit each of rice, eggs, chicken, sugar, flour, cooking oil, soy sauce, sardines, fish and tea",
        "Matched premises only. Sabah and W.P. Labuan are excluded (too few premises for rice or chicken); "
        "Perlis has no matched fish prices.",
    )
    save(fig, "q4_basket_cost.png")


if __name__ == "__main__":
    load_dotenv(PROJECT_DIR / ".env")  # PG* settings; psycopg reads them automatically
    CHART_DIR.mkdir(parents=True, exist_ok=True)
    plt.rcParams["font.family"] = ["Segoe UI", "DejaVu Sans"]

    with psycopg.connect() as conn, conn.cursor() as cur:
        q1_states, _, _ = run_sql_file(cur, "05_q1_state_inflation.sql")
        chart_state_inflation(q1_states)
        chart_category_heatmap(cur, q1_states)   # reuses Q1's cpi_yoy view

        # First and last month of price data, for chart labels (fast: fact_prices.date is indexed)
        first_month, last_month = cur.execute("SELECT min(date), max(date) FROM mart.fact_prices").fetchone()

        q2_risers, q2_fallers = run_sql_file(cur, "06_q2_item_price_change.sql")
        chart_item_changes(q2_risers, q2_fallers, first_month, last_month)

        q3_types, _ = run_sql_file(cur, "07_q3_premise_type_prices.sql")
        chart_premise_types(q3_types)

        _, _, q4_change, _ = run_sql_file(cur, "08_q4_basket_cost.sql")
        chart_basket(q4_change, first_month, last_month)
