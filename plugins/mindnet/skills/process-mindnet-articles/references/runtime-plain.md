# Runtime: Claude Code

For a session of the MindNet plugin in Claude Code: the MindNet MCP
tools, the files, maybe a shell. Everything here is on top of SKILL.md.

## What you do not build

- **One session, articles one after another.** Do not start other
  sessions or agents to work on articles in parallel — through a session
  manager, a desktop or cloud MCP tool or a background CLI. Those are
  agents nobody watches, holding the reader's key.
- **No subagents for the checks.** A Claude subagent (`Agent`, `Task`…) is
  the same family and is never a checker of Claude text; the checks are
  your own passes (below).
- **A schedule only through `/mindnet:setup`** (below). No other cron,
  loop or routine of your own.

## Scheduled runs

A reader who does not want to ask every time can have the queue processed
regularly. `/mindnet:setup` sets that up: it checks the connection and,
when the person agrees, creates **one** recurring run — a scheduled task
of the Claude desktop app, a `/loop` in the open session, or a launchd or
cron job with `claude -p`. Rules:

- **Only when the person asks.** Set up, change or remove the schedule
  when the person asks for it in the session — they ran `/mindnet:setup`,
  or said „zpracovávej to pravidelně“, „každou hodinu“, „zruš plán“. Then
  go by the steps of `/mindnet:setup`. Never on your own initiative: not
  because the queue is long, not because a run ended with articles still
  waiting. Then say how many wait and that `/mindnet:setup` sets up
  regular runs.
- **One MindNet schedule at most.** Before creating one, look for the
  existing one (the desktop task `mindnet-articles`, a launchd job
  `app.mindnet.agent`, a crontab line ending in `# mindnet`) and change it
  instead of adding a second.
- **A scheduled run is an ordinary run** (below), started by a prompt that
  begins „MindNet scheduled run“. It calls `status` first and, when
  `waiting` is empty, ends at once with one line — most scheduled runs
  are that, so keep them short: no table, nothing loaded. The cap of six
  articles holds; the next scheduled run takes the rest.
- **Nobody watches a scheduled run.** When something needs a person — the
  tools are missing, the key is rejected, a tool asks for a permission —
  end with one line saying what and do not repair the configuration.

## The run

A person asked („zpracuj moje články“, „jsou tam nové články?“), or the schedule the person set up with `/mindnet:setup` started the run (see „Scheduled runs“ above). One
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
same „what to do with the findings — once“. What a clean context and another model family would give you, you replace by three disciplines:

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
