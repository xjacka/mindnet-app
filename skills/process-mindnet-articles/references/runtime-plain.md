# Runtime: plain harness

For a session in Claude Code, Codex CLI, Cursor or any other agent that
has the MindNet MCP tools and not the DAM platform (no `schedule_once`,
no `spawn_subagent`, no `[mindnet:…]` marker — SKILL.md, „Which runtime
you are on“). Everything here is on top of SKILL.md.

## What is not here, and what you do not imitate

A plain harness has none of DAM's machinery. Do not build a substitute
for it — each substitute breaks something the server or the rules rely
on:

| DAM has | here | why not imitate it |
|---|---|---|
| scheduled jobs, the dispatcher, the preflight (`precheck.py`, onboarding) | a person starts the run; you call `status` yourself | a cron, loop or routine you set up yourself is a standing job nobody asked for; the person decides when the agent runs |
| `schedule_once`: one parallel session per article | one session, articles one after another | starting sessions through another tool (a session manager, a desktop or cloud MCP tool, a background CLI) is starting agents nobody watches, with your key |
| GPT checks in platform sub-agents (`check.sh`, `judge.py`) | the checks are your own passes | the scripts need DAM's driver SDK and LiteLLM and fail here; a Claude subagent (`Agent`, `Task`…) is the same family and is never a checker of Claude text |
| a shared pod with check slots | nothing to share | — |

So in a plain run you **do not**: run anything from `scripts/`, read
[onboarding.md](onboarding.md), create scheduled or recurring jobs, start
other sessions or agents, or launch subagents. When the person wants the
queue processed regularly, say that this skill sets up the schedule only
on DAM; here they start the run again when they want it, by whatever means
their harness offers them.

## The run

A person asked („zpracuj moje články“, „jsou tam nové články?“). One
session handles the articles **one after another**:

1. `status`. An empty `waiting` → tell the person nothing waits (and how
   many articles are `in_progress` in other runs of theirs, which are not
   yours) and end.
2. `claim_article` → one article. `{ empty: true }` → another run took it;
   back to 1.
3. Carry the article to the end by the table in SKILL.md, „One run“. For
   `processing`, wait about a minute — `sleep 60` in a shell when you have
   one — then `claim_article` with `{ job: job_id }`.
4. When the article is over, back to 1. Never claim the next article
   before the current one is over: its leases run from the claim.
5. Stop when `status` shows nothing waiting, or after **six articles**
   unless the person said how many — the context of one session should
   not carry more. Say how many still wait; the person starts the next
   run.

Carry nothing from one article to the next — not the reader's settings,
not the previous article's names or figures, not the previous thread's
style. Every prompt is complete in itself (SKILL.md, „Settings change and
so do prompts“). Before each `fragment`, re-read
[phase-a.md](phase-a.md) if anything of the previous article blurs into
the new one.

## The checks as your own passes

You run the extractor, the cold reader and the fidelity reviewer yourself,
in the order of [phase-a.md](phase-a.md), with the same templates and the
same „what to do with the findings — once“. What the clean context and the
other family gave you on DAM, you replace by three disciplines:

- **Write each pass out before the next step.** Its result is a written
  list in the template's shape, not an impression. A list made in your
  head after the cards are written is made by the writer and confirms the
  writer.
- **Search, do not remember.** Whatever can be checked mechanically, check
  mechanically. When you have a shell, save the article block from the
  prompt to a scratch file and search it for every figure, name and
  excerpt (`grep -F`); without a shell, find each one in the prompt text
  itself. A figure you cannot find is not in the article.
- **Answer from the text in front of you, not from the article in your
  head.** The cold reader's questions are answered from the flattened
  card alone; the fidelity questions from the article alone.

The passes, in the 18-minute budget of SKILL.md:

1. **Extractor (≤ 4 min), before any outline or card.** Read the article
   and fill the extractor template's JSON in full: core ideas, facts,
   quotes, context, ending, each with `[¶n]` and a verbatim excerpt. Write
   it down whole. It is still the list completeness is checked against —
   it was made before any card existed, which is what the rule needs.
   Over ~3,000 words go by thirds and merge.
2. **Outline, plan, cards (≤ 6 min)** — as phase-a.md says.
3. **Cold reader (≤ 2 min).** Flatten the cards to plain text, exactly as
   the cold reader would get them (lead, blocks, no key facts, no
   outline). For each card, from that text only: what it teaches in one
   sentence (or DESCRIPTION), who · what · when · setting · why it
   matters, every name a reader could not place without a `[[…|…]]`
   mark, every pronoun, generic noun or relative time pointing outside
   the card, the frame in the first sentence, and pairs of cards that
   teach the same thing. Then for every vital fact the card that carries
   it, or NOWHERE. This pass is the weakest without a clean context —
   you know what each card means — so be literal: for every noun the claim
   stands on, ask „of what?“ and „whose?“, and if the card does not say
   it, write MISSING even when it is obvious to you.
4. **Fidelity reviewer (≤ 2 min).** Against the article: search for every
   figure (with its unit), name, date and quote on every card; check that
   each claim keeps its caveat (sample, setting, condition); go through
   the extractor list item by item and write the card that carries each
   core idea and the ending, or `missing_ideas`; note duplicates and a
   stronger quote left unused. Report in the fidelity template's shape.
5. **One revision (≤ 3 min)**, the gate step by step (phase-a.md), the
   checklist „Before you write the answer“, the answer. No second pass.

In the report: „checks: own passes (plain harness, no other-family
reviewer)“ and what the passes changed. Do not claim a GPT or an
independent check that did not happen.

## Translate: the proofreading pass

For `translate` into a language with diacritics, after all drafts of the
article and before any answer, one pass over all cards (SKILL.md, „The
checks“). Read only the translations, in order, as a native editor of the
target language — not against the original. Then the mechanical part,
in a shell when you have one:

- an em dash `—` in a Czech or Slovak text → a spaced en dash ` – `;
- a card body or block with no non-ASCII character in a diacritic
  language → it is not translated;
- an English word outside the glossary's kept terms → translate it or
  check the policy;
- the ASCII double quote `"` inside a text value → typographic quotes.

Fix `final` body and blocks, then answer. Fidelity to the original is the
draft's job, not this pass's.
