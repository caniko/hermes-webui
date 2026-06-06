from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI_JS = (ROOT / "static" / "ui.js").read_text(encoding="utf-8")
STYLE_CSS = (ROOT / "static" / "style.css").read_text(encoding="utf-8")


def test_tool_cards_use_legacy_compact_header_without_tool_output_badge():
    """Tool cards keep the legacy compact header: icon, tool name, preview."""
    build_start = UI_JS.index('function buildToolCard(tc){')
    build_end = UI_JS.index('function _syncToolCallGroupSummary', build_start)
    build_tool_card = UI_JS[build_start:build_end]

    assert 'tool-card-badge' not in build_tool_card
    assert 'Tool output' not in build_tool_card
    assert '<span class="tool-card-name">${esc(displayName)}</span>' in build_tool_card


def test_tool_card_badge_style_is_absent():
    assert '.tool-card-badge{' not in STYLE_CSS
    assert '.tool-card:hover .tool-card-badge' not in STYLE_CSS


def test_tool_cards_use_legacy_muted_rail():
    # #3401 restyled the tool card: the muted background + muted rail are now set
    # with !important and the left rail color is pinned via border-left-color
    # (var(--border2)) rather than a `border-left:2px solid var(--border-muted)`
    # shorthand. The invariant is unchanged — tool cards use a MUTED rail, never the
    # bright accent rail — so assert the new form + the still-forbidden accent rail.
    assert '.tool-card{background:var(--surface-subtle)!important;' in STYLE_CSS
    assert 'border-color:var(--border-muted)!important' in STYLE_CSS
    assert 'border-left-color:var(--border2)!important' in STYLE_CSS
    assert 'border-left:3px solid var(--accent-bg-strong)' not in STYLE_CSS
