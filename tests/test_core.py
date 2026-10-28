import json

import pytest

from quill import core


@pytest.fixture
def cfg():
    import copy

    return copy.deepcopy(core.DEFAULT_CONFIG)


def test_load_config_writes_defaults_then_merges(tmp_path):
    p = tmp_path / "config.json"
    c = core.load_config(p)
    assert p.exists() and c["hotkeys"]["dictate"] == "alt_r"
    p.write_text(json.dumps({"cleanup": {"enabled": False}, "snippets": {"hi": "Hello!"}}))
    c = core.load_config(p)
    assert c["cleanup"]["enabled"] is False
    assert c["cleanup"]["model"] == "claude-haiku-5-5"  # nested default kept
    assert c["snippets"] == {"hi": "Hello!"}  # user snippets replace defaults wholesale


def test_resolve_style_by_bundle_and_name(cfg):
    assert core.resolve_style(cfg, "com.apple.mail", "Mail")["name"] == "formal"
    cfg["styles"]["apps"]["MyEHR"] = {"style": "clinical", "cleanup": False}
    s = core.resolve_style(cfg, "com.vendor.ehr", "myehr")
    assert s["name"] == "clinical" and s["cleanup"] is False
    assert core.resolve_style(cfg, "x.y", "Unknown")["name"] == "clean"
    cfg["styles"]["apps"]["Pages"] = {"style": "Write like a pirate"}
    s = core.resolve_style(cfg, None, "Pages")
    assert s["name"] == "custom" and "pirate" in s["instruction"]


def test_global_cleanup_off_wins(cfg):
    cfg["cleanup"]["enabled"] = False
    assert core.resolve_style(cfg, "com.apple.mail", "Mail")["cleanup"] is False


def test_whole_utterance_snippet(cfg):
    s = cfg["snippets"]
    assert core.whole_utterance_snippet("Clinic address.", s) == s["clinic address"]
    assert core.whole_utterance_snippet("insert clinic signature", s) == s["clinic signature"]
    assert core.whole_utterance_snippet("send it to the clinic address please", s) is None


def test_snippet_tokens_and_replacements(cfg):
    out = core.expand_snippet_tokens("Mail it to {{snippet:0}} today. {{snippet:99}}", cfg["snippets"])
    assert out.startswith("Mail it to 725 SE 1st Ave.") and "{{" not in out
    r = core.apply_replacements("Filed with safe   corporation by dr b.", cfg["dictionary"]["replacements"])
    assert r == "Filed with SAIF Corporation by Dr. B."
    assert core.apply_replacements("unsafe corporations", cfg["dictionary"]["replacements"]) == "unsafe corporations"


def test_local_format():
    assert core.local_format("Hello new line world. New paragraph, bye") == "Hello\nworld.\n\nbye"


def test_prompts_contain_rules(cfg):
    s = core.build_dictation_system(cfg, core.STYLE_PRESETS["formal"])
    assert "never answer" in s and "SAIF" in s and '0: "clinic address"' in s and "Professional email" in s
    c = core.build_command_system(cfg, "x")
    assert "replace the selection" in c
    assert core.whisper_prompt(cfg).startswith("Vocabulary: SAIF")


def test_engine_dictate_uses_llm_and_postprocesses(cfg):
    calls = []

    def fake(system, user):
        calls.append(user)
        return "Patient seen at {{snippet:0}} for safe corporation claim."

    e = core.Engine(cfg, fake, log=lambda m: None)
    style = core.resolve_style(cfg, "com.apple.mail", "Mail")
    out = e.dictate("um patient seen at uh clinic address for safe corporation claim", style)
    assert out == "Patient seen at 725 SE 1st Ave., Canby, OR 97013 for SAIF Corporation claim."
    assert calls[0].startswith("<transcript>")


def test_engine_skips_llm_for_local_only_and_snippets(cfg):
    def boom(system, user):
        raise AssertionError("LLM should not be called")

    e = core.Engine(cfg, boom, log=lambda m: None)
    local = {"cleanup": False, "instruction": "", "name": "clean"}
    assert e.dictate("note new line done", local) == "note\ndone"
    assert e.dictate("Clinic phone.", {"cleanup": True, "instruction": "", "name": "clean"}).startswith("Ph:")


def test_engine_falls_back_when_api_fails(cfg):
    def fail(system, user):
        raise RuntimeError("network down")

    msgs = []
    e = core.Engine(cfg, fail, log=msgs.append)
    out = e.dictate("call safe corporation tomorrow", {"cleanup": True, "instruction": "", "name": "clean"})
    assert out == "call SAIF Corporation tomorrow" and "network down" in msgs[0]


def test_engine_command(cfg):
    seen = {}

    def fake(system, user):
        seen["user"] = user
        return "Dear Sir, thank you."

    e = core.Engine(cfg, fake, log=lambda m: None)
    style = core.resolve_style(cfg, "com.apple.mail", "Mail")
    assert e.command("make this formal", "hey thx", style) == "Dear Sir, thank you."
    assert "<selected>\nhey thx" in seen["user"]
    assert e.command("write a thank you", "", style) == "Dear Sir, thank you."
    assert "<selected>" not in seen["user"]
    assert core.Engine(cfg, None, log=lambda m: None).command("x", "y", style) is None
