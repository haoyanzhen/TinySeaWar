# Design Document Audit Criteria

Use this reference while classifying findings and file disposition. Apply judgment; severity and disposition are not derived from raw counts.

## Contents

1. Per-document evidence card
2. Review dimensions
3. Ownership rules by document family
4. Disposition decision matrix
5. Deletion and archive gates
6. Rewrite quality checks
7. Final consistency matrix

## 1. Per-document evidence card

Record one card per file:

| Field | Required evidence |
|---|---|
| File | Current path, title, line count |
| Intended function | One sentence from the document opening |
| Actual content | Major sections and claim types |
| Owns | Concepts for which this is the authoritative source |
| Must not own | Concepts delegated elsewhere |
| Consumers | Docs, code, data, tests, tools, or routes referencing it |
| Completeness gaps | Missing inputs, outputs, states, errors, edge cases, or validation |
| Overlap | Exact duplicated concepts and competing owner |
| Contradictions | Claim, conflicting evidence, and selected authority |
| Stale content | Old names, paths, status, phase assumptions, examples, or tests |
| Excess | Text removable without loss of executable meaning |
| Proposed disposition | Keep, Tighten, Split, Merge, Archive, Delete candidate |
| Required follow-up | Destination files, routes, tests, status, or authorization |

## 2. Review dimensions

### Boundary clarity

High priority:

- two active files both call themselves the source of truth;
- a file has no opening function/boundary statement;
- gameplay, schema, Domain, status, and implementation path are mixed;
- an audit/history file remains in the active route;
- a document title or filename describes an obsolete phase rather than its current role.

### Completeness

Check only dimensions relevant to the document:

- inputs and outputs;
- state ownership and mutation authority;
- lifecycle and terminal states;
- command, event, rejection, and error semantics;
- ordering and deterministic behavior;
- hidden-information or permission boundary;
- configuration references and loading validation;
- integration points and acceptance tests.

Do not inflate an overview or index into a detailed contract. Completeness means fulfilling the stated responsibility, not containing everything.

### Duplication

Remove or delegate:

- copied formulas or numeric tables;
- copied enum/field tables;
- repeated current completion summaries;
- code path inventories outside the implementation map;
- repeated implementation history and test counts;
- copied input instructions, AI weights, asset paths, or art specifications;
- multiple long explanations of the same motivation.

Retain:

- a short local invariant needed to understand the contract;
- an explicit dependency sentence with a link;
- a concise example that tests a unique local edge case.

### Contradiction

Treat as high priority when it changes:

- result semantics, probability floors, formula order, or legal actions;
- data enum or exact runtime ID;
- radar/observation permissions or hidden information;
- implemented versus unimplemented status;
- active path, file count, level count, sample count, or acceptance result;
- who owns a state or may mutate it.

Verify against code/data/tests/reports before editing. A dated historical statement may remain when clearly scoped to its date.

### Excess prose

Delete or compress text that:

- repeats the title or project premise;
- predicts uncommitted future work outside the document’s role;
- narrates step-by-step implementation history in an active contract;
- provides multiple examples proving the same rule;
- lists obvious directory structures already owned by `34`;
- uses recommendation language after a decision is already current;
- restates another document’s complete section before linking it.

Preserve rationale when it explains a non-obvious tradeoff, guards against a known failure mode, or determines future implementation choices.

## 3. Ownership rules by document family

| Family | Owns | Must delegate |
|---|---|---|
| `00` | Current completion, gaps, latest verification, priorities | Full rules, schemas, implementation design |
| `10–19` | Gameplay intent, formulas, balance budgets, level/AI/experience/environment/simulator semantics | Exact schema tables, code paths, current completion |
| `20` | Schema index and common data conventions | Detailed category fields |
| `21–26` | Field names, types, required/default, enum, reference, loading validation | Gameplay rationale, Domain state machines, code paths, status |
| `30` | Architecture layers, dependencies, topology, technical principles | Gameplay rules, schema tables, current paths/status |
| `32` | Core battle Domain state, commands, events, order, services | Scene subdomains, AI scoring, presentation |
| `33` | Snapshot/event-to-view architecture and presentation lifecycle | Art specs, rule calculation, asset physical paths |
| `34` | Current file/code/data/test location | Rules, values, completion judgments |
| `35` | Hard terrain and spatial queries | Weather/environment state, facility lifecycle |
| `36` | Experiment comparison, statistics, gates, conclusion lifecycle | Simulator platform internals, gameplay targets |
| `37` | Environment runtime state and context composition | Effect values, hard geometry, facility lifecycle |
| `38` | Facility/mine state, ownership, tasks, commands, events | Effect values, hard geometry, art/UI |
| `technical/` | One cross-system implementation solution and its acceptance plan | Replacement of architecture/Domain truth |
| `40–49` | Art direction, presentation specifications, asset interfaces/pipeline | Combat rule calculation and current completion |
| `90–99`, `history/` | Historical evidence and superseded decisions | Current truth |

If the repository later changes this map, update `AGENTS.md` first and adapt the audit; do not freeze obsolete ownership in this reference.

## 4. Disposition decision matrix

| Signal | Keep | Tighten | Split | Merge | Archive | Delete candidate |
|---|---:|---:|---:|---:|---:|---:|
| One active responsibility | Strong | Strong | Against | Neutral | Against | Against |
| Useful unique current contract | Strong | Strong | Possible | Possible | Against | Prohibits |
| Copied truth but correct owner | Neutral | Strong | Weak | Weak | Weak | Against |
| Multiple stable domains | Against | Weak | Strong | Against | Weak | Against |
| Same responsibility as another active file | Against | Weak | Weak | Strong | Possible | Possible |
| Obsolete phase/status but historical rationale | Against | Weak | Against | Possible | Strong | Against |
| Generated/empty/exact duplicate, no historical value | Against | Against | Against | Against | Weak | Strong |
| Many active inbound consumers | Strong | Strong | Requires migration | Requires migration | Requires migration | Requires migration |
| Long file only | Neutral | Neutral | Not sufficient | Not sufficient | Not sufficient | Not sufficient |

## 5. Deletion and archive gates

### Archive gate

Answer yes to all:

- Is the file no longer authoritative?
- Is there a clear current replacement or is it explicitly historical?
- Would keeping it in active order mislead future work?
- Does it contain useful context worth preserving?
- Can all active inbound references be migrated?

Required treatment:

- move to `docs/history/`;
- prepend archive notice;
- route only under history;
- update active references;
- keep original content substantially intact unless unsafe or misleading without annotation.

### Delete gate

Answer yes to all:

- Is there no unique current content?
- Is there no useful historical rationale?
- Have generated/source relationships been checked?
- Have all inbound references and tooling assumptions been found?
- Has any unique fragment been migrated?
- Is Git history sufficient?
- Did the user explicitly authorize deleting this named file?

If any answer is no, do not delete. Prefer Tighten, Merge then Archive, or report a Delete candidate.

## 6. Rewrite quality checks

For each rewritten active document:

- opening function/boundary is understandable without reading another file;
- every major section fits that boundary;
- title and filename are current enough to route correctly;
- no current status appears outside an authorized status/testing document;
- no full formula, schema, path table, or test history is copied from its owner;
- terminology, IDs, enums, percentages, and paths match repository evidence;
- links point to current active or intentionally archived paths;
- edge cases and rejection semantics remain explicit;
- shorter text has not removed an invariant needed for implementation;
- proposed/future language is labeled and does not masquerade as current state.

## 7. Final consistency matrix

Before finishing, confirm:

| Changed concept | Required synchronization |
|---|---|
| Current completion or validation | `00`, concise `AGENTS.md` summary |
| Gameplay rule | Owning `10–19`, formula/data/Domain/operation dependents as applicable |
| Field/schema | Owning `21–26`, loader, tests, data; `20` only if index/common rule changes |
| Domain responsibility | `30/32/35/37/38`, affected schemas and technical solutions |
| Presentation responsibility | `33`, `25`, `40–49`, implementation map |
| File move/split/archive/delete | All inbound references, `AGENTS.md`, `docs/README.md`, `34` when locations change |
| Code/data correction | Relevant tests and actual validation result in `00` |
| Historical-only conclusion | Audit/history route, not current summary |

The audit is incomplete if any row has an unsynchronized required target.
