"""Independent cleanup tasks: repair mistakes without losing names or meaning."""
from __future__ import annotations

import re
import textwrap
from pathlib import Path


def production_prompts(root: Path) -> dict[str, str]:
    source = (root / "Sources/Services/CorrectionPrompt.swift").read_text()
    match = re.search(r'static let template = """\n(.*?)\n\s*"""', source, re.S)
    integrity_source = (root / "Sources/Services/CorrectionIntegrity.swift").read_text()
    integrity_match = re.search(r'static let instruction = """\n(.*?)\n\s*"""', integrity_source, re.S)
    assert match is not None and integrity_match is not None
    prompt = textwrap.dedent(integrity_match[1]) + "\n\n" + textwrap.dedent(match[1])
    # Categories remain corpus labels; production now uses one prompt everywhere.
    return {category: prompt for category in ("terminal", "coding", "chat", "writing", "email", "general")}


def cases() -> list[dict]:
    rows = [
        ("terminal", "um run suit oh apt update then see dee into documents", ["sudo", "cd"], ["apt", "update", "documents"], [], ["um"]),
        ("terminal", "open eye term and uh run git status", ["iTerm"], ["git", "status"], [], ["uh"]),
        ("terminal", "run grep dash v error then pipe to less", ["grep", "less"], ["error"], [], []),
        ("terminal", "Do not run rm on the backup folder. Run ls first.", [], ["not", "rm", "backup", "ls", "first"], [], []),
        ("terminal", "ssh -p 2222 dev@example.test and keep the port 2222", [], ["ssh", "2222", "dev@example.test"], [], []),
        ("coding", "use a sink await and a four loop in the function", ["async", "for loop"], ["await", "function"], [], []),
        ("coding", "set you state to false and keep handleSubmit camelCase", ["useState"], ["false", "handleSubmit"], [], []),
        ("coding", "The JSON API returns 404, not 200. Keep the retry disabled.", [], ["JSON", "API", "404", "not", "200", "disabled"], [], []),
        ("email", "hi sarah um please sand the attach meant by friday best regards morgan", ["send", "attachment"], ["Sarah", "Friday", "Morgan", "best regards"], [], ["um"]),
        ("email", "hi jordan please do not send the invoice until i approve it thanks priya", [], ["Jordan", "not", "invoice", "approve", "Priya"], [], []),
        ("email", "Please keep the invoice at $21.50, including taxes, and send it to Mateo.", [], ["$21.50", "including taxes", "Mateo"], [], []),
        ("email", "Hi Siobhan, I cannot approve Thursday, but Tuesday is fine.", [], ["Siobhan", "cannot", "Thursday", "Tuesday"], [], []),
        ("general", "their going to the store tomorow", ["they're", "tomorrow"], ["store"], [], []),
        ("general", "check weather or not the deploy went through", ["whether"], ["deploy"], [], []),
        ("general", "uh remind me to call the dentist tomorrow morning", [], ["dentist", "tomorrow", "morning"], [], ["uh"]),
        ("general", "I like this approach. Do not remove the word like.", [], ["like", "not", "remove"], [], []),
        ("general", "Send the report (including taxes) to Jordan [the editor].", [], ["including taxes", "Jordan", "the editor"], [], []),
        ("general", "The balance is negative $42. Do not turn that into a positive balance.", [], ["negative", "$42", "not", "positive"], [], []),
        ("writing", "right a function to read there config file", ["write", "their"], ["function", "config"], [], []),
        ("writing", "um the release is on monday and uh testing is on tuesday", [], ["release", "Monday", "testing", "Tuesday"], [], ["um", "uh"]),
        ("writing", "We must not publish version 3.1.4 before October 5.", [], ["not", "3.1.4", "October", "5"], [], []),
        ("writing", "The deployment failed. We have not confirmed recovery yet.", [], ["failed", "not", "confirmed", "yet"], [], []),
        ("chat", "brb uh send the you are ell when you can lol", ["URL"], ["brb", "lol"], [], ["uh"]),
        ("chat", "yeah um i can do tuesday but not thursday", [], ["Tuesday", "not", "Thursday"], [], ["um"]),
        ("chat", "sure thing /s — do not make that sound like agreement", [], ["not", "agreement"], [], []),
        ("general", "Document our thinking process: first we scope, then we test.", [], ["thinking process", "scope", "test"], [], []),
        ("general", "The project is called Qwen, and the client is Priya, not Maria.", [], ["Qwen", "Priya", "not", "Maria"], [], []),
        ("email", "Hello Morgan, the refund is $125, not $152. Please check the amount.", [], ["Morgan", "$125", "not", "$152"], [], []),
    ]
    result = [dict(id=f"writing-{index}", category=category, input=text, fixes=fixes, keep=keep, forbid=forbid, drop=drop, literal=[], aliases={})
              for index, (category, text, fixes, keep, forbid, drop) in enumerate(rows)]
    # Command punctuation is meaningful; ASR-style normalization erases it.
    result[2]["literal"] = ["-v", "|"]
    result[4]["literal"] = ["-p 2222", "dev@example.test"]
    result[24]["literal"] = ["/s"]
    # Accept legitimate grammatical forms. "Whether or not" has optional
    # "or not"; this is not equivalent to losing negation in "do not delete".
    result[7]["aliases"] = {"disabled": ["disable"]}
    result[8]["aliases"] = {"attachment": ["attachments"]}
    result[11]["aliases"] = {"cannot": ["unable to approve", "Thursday is not acceptable"]}
    result[13]["aliases"] = {"deploy": ["deployment"], "whether": ["if"]}
    # This input does not establish ownership, so "the config" is also a
    # reasonable repair of "there config". Accept it without forcing a rewrite.
    result[18]["aliases"] = {"config": ["configuration"], "their": ["the config", "the configuration"]}
    return result
