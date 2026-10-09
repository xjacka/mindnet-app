# What the prompt measurements showed — and what follows for you

Sources: `docs/FRAGMENTY-RESEARCH.md` (research of 12 September 2026 and
measurements of 12–13 September), `docs/PLAN-FRAGMENTY.md`,
`docs/REVIZE-EXTRAKCE-A-PREKLADU.md` (review of 28 September), ADR-0011,
ADR-0017. The figures come from the prompt lab (`tools/lab`) over three to
four test articles, the genre lab (`tools/lab/genre`, 26 articles, blind
raters) and the translation lab (`tools/lab/translate`, 20 cards).

## What broke in v7 and what v8 with the gate did about it

| flaw | v7 (157 cards, Haiku) | v8 + gate (28 cards, gpt-oss-120b) |
|---|---|---|
| the `stat` figure repeated in words in the lead | 28 | **0** |
| a figure that is not in the article | — | **0** |
| first sentence unanchored | 12 | 1 (dropped by the gate) |
| meta-description / marketing superlative | 4 + 4 | 0 |
| dropped by the gate | — | 1 of 28 (4 %) |

For you: the gate exists because the prompt **promises** and the model,
under thirty other rules, forgot. You have time to reread yourself; do it
and do not rely on the gate to fix you — on hard findings the card simply
vanishes, on soft ones it drops below the threshold.

## What stayed open — and where you add the most

1. **The `text` style did not keep the sentence count**: 12 of 16 cards
   were one long sentence instead of 3–4. Sentence count is what models
   keep in 96–99 % of cases (a word range only in 27–80 %) — which is why
   the prompt uses it instead of words. Count sentences.
2. **Translation into Czech by a small model was bad**: 30 % of cards
   partly English, 44 % with a grammar error. That is the `translate`
   request and the place where a strong model changes the result most.
   The lab of 28 September with the v3 prompt (context, glossary, policy,
   two passes) on the same small model: terminology errors halved,
   fluency up, but more accuracy errors — the second pass may drift.
3. **Free tiers saw only a piece of the article.** The v8 prompt had
   13,500 characters and Groq's input ceiling is 16,000, so the model saw
   16–19 % of the `ibm` article. The measured completeness (0.21–0.47 for
   v8) measured the budget, not the prompt. You see the whole article —
   completeness is therefore **your responsibility**, not an excuse: the
   outline and the coverage of the last third are not a formality.
4. **Faithfulness of v8 was demonstrably higher**: 1.00 for `rich` and
   `number` against 0.85 for v7, the interval of the difference not
   crossing zero. Keep it: verbatim figures and names, nothing outside the
   article.

## What the text-type lab showed (28 September 2026)

Text-type modules (`genre`) against the generic prompt over 26 articles in
13 types; two independent blind raters in round r4: 42 wins, 6 draws, 8
losses for the module. News, survey, essay, social post, review,
announcement and explainer are on in production; how-to, research and law
lost in r3 (partly because extraction lost short paragraphs and tables —
fixed on 28 September, to be re-measured); interview, digest and feature
were never independently rated. The module refines what to pick and what
element the card stands on; the core rules hold unchanged.

## What the judge and the measuring apparatus showed (13 September 2026)

- Faithfulness and completeness the judge returns exactly on repeat;
  conciseness and standalone-ness fluctuate, because they arise from
  per-card decisions. Your own „cold reader“ check is therefore
  indicative, not decisive — when unsure, anchor the card more, not less.
- Judges see **added** claims (0.79–0.94), **omitted** ones not
  (0.50–0.63). The question „is anything missing?“ is blind. The only
  thing that works is a list of facts checked one by one — hence the
  „outline“ step.
- Models favour their own text (MSumBench; Wataoka et al. 2024). When
  checking your own cards, look for errors, not confirmation.
- Six findings of the measuring apparatus shared one pattern: **someone
  else decided the result and nobody verified they kept their promise** —
  the schema forbade a `null` the prompt itself asked for and the model
  made up a field `sentence_null`; the cold reader quoted a word from the
  prompt instead of the card. For you: verify the shape of the answer
  against what the prompt prints, not against what would make sense. A
  field you invent silently disappears.

## From the literature, with direct impact on writing cards

- Facts first, text from them, check separately: SumCoT +4 ROUGE-L,
  Self-Planning +35 % SummaC; chaining steps beats one long prompt.
- A verbatim excerpt for every fact is the cheapest brake on
  hallucination; „when you find no quote for a claim, drop the claim“.
- Models take disproportionately more from the first 20 % of the text and
  short outputs amplify it — hence the last-third rule.
- The main flaw of summaries that pass a fact check is **separating the
  evidence from the caveat** that qualifies it (Lee et al. 2026). The
  figure belongs on the card with the condition under which it holds.
- Reasoning mode hurts faithfulness (o3-pro 23 %, R1 11 % vs V3 6 %); 72 %
  of R1's hallucinations were true additions outside the source. Reason
  about whether the article says it — not about what you know.
- Abstractive output raises perceived usefulness, but verifiability falls
  by up to half (Worledge et al. 2024). Paraphrase the connecting text, not
  the data.
- Decontextualisation has a category INFEASIBLE — about 10 % of sentences
  cannot be made standalone. Omission is a legitimate result, not a failure.
- People prefer the third of five densification steps (Chain of Density):
  every sentence carries a name or a figure, but more than one
  densification pass hurts coherence. Dense, not telegraphic.
- Translation: keywords and glossary before translating (MAPS, He et al.
  2023) keep terms consistent; a second „read as a native editor“ pass
  (Chen et al. 2023; Raunak et al. 2023) raises naturalness; error-span
  annotation by category (GEMBA-MQM, Kocmi & Federmann 2023) measures
  better than a 1–5 grade.

## Why the checks run in another context on another model (15 September 2026)

The agent runs on Opus or Sonnet, cost is not the issue, but everything
goes in one thread. Subagents get a clean context and the other model,
for four reasons from the research:

- **Decontextualisation is tested without the document.** Choi et al.
  2021 define a standalone sentence as „interpretable in an empty
  context“; QaDecontext (Newman et al. 2023) and Claimify (2025) measure
  it with a cold reader's questions over the text **without the source**.
  Whoever has just read the article cannot run that test — everything
  makes sense to them.
- **Models favour their own text** (MSumBench 2025; Wataoka et al. 2024).
  The judge should be from another family; you have none, so at least
  another model and a context without your reasoning. In the lab Qwen
  judges for exactly this reason.
- **Judges see added, not omitted** (Fox et al. 2026: 0.79–0.94 vs
  0.50–0.63). Completeness is therefore checked by the subagent against
  the **list of vital facts**, each separately, not by „is anything missing?“.
- **Chaining steps beats one long prompt** (Sun et al. 2024: one prompt
  „only simulates refinement“). A check as a separate step with its own
  context is what a single thread otherwise cannot do.

And the reason for **only one revision** (since 6 October 2026 the
checks are two and run side by side, the fix is still one): every further
check-and-fix loop raises fluency, not faithfulness (Yuan & Zhang 2026:
reflective strategies lower AlignScore), and the run time is limited by
the deadline per answer.

## Why several rounds, and why still only one revision (6 October 2026)

The reader asked for threads that stand in for the article — core ideas,
facts worth remembering, strong quotes, context — with nothing repeated
and the idea before the attribution, and said the agent may work in
rounds and use subagents. Prompt `fragment.v15` carries the rules; the
rounds are the procedure that makes them reachable:

- Independent extraction before writing gives the list completeness is
  checked against (Fox et al. 2026: judges see added, not omitted). The
  extractor runs in a clean context so its list is a second reading, not
  an echo of yours.
- The cold reader without the article and the fidelity reviewer with it
  look for different things: the first for what the card fails to say,
  the second for what it says wrongly or drops (the caveat, Lee et al.
  2026), for two cards teaching the same thing, and for the attribution
  frame in the first sentence, which the coded gate passes.
- Reviews are reports, not rewrites; you rewrite once. After the one
  revision a card that still fails is anchored harder or dropped — never
  sent round again.
- Rounds cost time, not cards: the budget is 18 minutes from pick-up and
  the lease 20 (SKILL.md); a late subagent is skipped, not waited for.

