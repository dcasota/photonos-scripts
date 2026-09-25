# Replace Jev Engineering without Jev

Local decision layer for Claude Code on an RTX 4070 laptop GPU, keeping a Claude Max 20x subscription for generation.

Formatted Word original: [Jev-Engineering-Local-Claude-Code-Guide.docx](Jev-Engineering-Local-Claude-Code-Guide.docx).

**ENGINEERING PLAYBOOK**

**Replace Jev Engineering without Jev**

A local decision layer for Claude Code, using Ollama on an RTX 4070
laptop GPU, while keeping a Claude Max 20x subscription for generation.

  -----------------------------------------------------------------------
  **Field**         **Value**
  ----------------- -----------------------------------------------------
  Audience          Developer running Claude Code all day

  Writer            Claude Code on Anthropic Max 20x (\$200/mo)

  Judge             Local Ollama 7B--8B Q4 on RTX 4070 Laptop (8 GB VRAM)

  Exact rules       Hooks, allowlists, path guards --- no model

  Deliverables      This document + stage-local-jev.ps1 +
                    stage-local-jev.sh

  Date              24 September 2026
  -----------------------------------------------------------------------

**1. Purpose**

Jev Engineering is a work split, not a vendor lock-in: an LLM writes, a
cheap decision model picks or scores or answers yes/no, and code
enforces exact rules. TypeSafe Jev is one engine for the middle slot.
This playbook keeps Claude Code as the writer and puts a local Ollama
model in the judge slot so you do not send every micro-decision through
Opus, Sonnet, or a third-party API.

The bundled Windows and Linux staging scripts install that judge, wire
Claude Code hooks, and apply hardware and subscription guardrails
described below.

**2. The split that creates the boost**

A Claude Code session is mostly small judgments, not code generation.
Typical hidden questions:

-   Is this Bash / Write / Edit safe enough to auto-run?

-   Which standing rules apply to this prompt?

-   Which model tier should a subagent use?

-   Is this tool result still worth keeping in context?

If those go through Opus or Sonnet, you spend Max 20x quota and
multi-second latency on three-option questions. The boost comes from
moving those questions off the frontier model --- not from replacing
Claude as a coder.

  -----------------------------------------------------------------------
  **Step type**      **Owner**               **Example**
  ------------------ ----------------------- ----------------------------
  Creates text or    Claude (Sonnet / Opus / Implement the patch, write
  code               Fable)                  the test, explain the design

  Picks, scores,     Local Ollama judge      Allow / ask / deny this tool
  yes/no                                     call

  Follows an exact   Code and hooks          Never write .env; never rm
  rule                                       -rf /; stop after N actions
  -----------------------------------------------------------------------

**3. Target machine and subscription**

**3.1 RTX 4070 laptop GPU**

The GeForce RTX 4070 Laptop is an 8 GB card on a 128-bit bus. It is not
the 12 GB desktop 4070. Treat it as an 8 GB-tier machine. A 7B--8B Q4
instruct model with a 2k--4k context fits in VRAM. A 9B at 4k often
offloads a layer to CPU. A 14B Q4 does not fit. Long context is what
OOMs the card, not the weight file.

  -------------------------------------------------------------------------
  **Setting**          **4070 laptop value** **Why**
  -------------------- --------------------- ------------------------------
  Default judge model  qwen2.5:7b-instruct   Fits Q4 with KV cache left for
                                             4k context

  Fallback model       llama3.2:3b           If 7B pages or hook p95
                                             exceeds 2 s

  Do not pull for the  14B+, 9B at 8k+,      VRAM spill; hook budget missed
  live hook            coder 32B             

  Context length       4096 hard cap         KV cache is the OOM source

  Parallel slots       1 concurrent gen      One 8 GB resident model only

  Loaded models        1 model resident      No second model stealing VRAM

  Keep-alive           Never unload (-1)     Cold load is 5--15 s; hooks
                                             cannot wait

  Flash attention      Enabled               Smaller KV cache on NVIDIA

  Hook timeout         3 seconds, fail open  A hung gate is worse than no
                                             gate

  State sent to the    ≤ 2 000 characters    Never the full Claude
  judge                                      transcript
  -------------------------------------------------------------------------

+-----------------------------------------------------------------------+
| **Laptop display compositor**                                         |
|                                                                       |
| Leave \~1.0--1.5 GB VRAM for Windows or Linux desktop composition. If |
| Ollama reports layer offload, drop to 3B or cut context to 2048. Do   |
| not chase 9B quality on the live PreToolUse path.                     |
+-----------------------------------------------------------------------+

**3.2 Claude Max 20x**

Max 20x is Anthropic's top individual tier: about \$200/month, 20× Pro
per rolling 5-hour session, plus a weekly cap across models and a
separate Sonnet weekly cap. Usage is shared with claude.ai. Fable 5.1,
where available, is capped at 50% of the weekly allowance. There is no
unlimited plan. Headless / GitHub Actions usage may draw a separate
monthly credit pool equal to the plan price. Recheck Settings → Usage
and /usage inside Claude Code; published hour counts move.

  -----------------------------------------------------------------------
  **Quota fact**             **Implication for this design**
  -------------------------- --------------------------------------------
  5-hour session + weekly    Local judge exists to stop burning that cap
  cap still exist            on micro-decisions

  Chat and Claude Code share Do not also run long claude.ai chats during
  the pool                   a heavy coding day

  Opus and Fable drain the   Reserve them for design and hard refactors
  week faster                

  Haiku is on the plan       Emergency fallback judge if Ollama is down
                             --- not the default

  Parallel Claude Code       One heavy session plus local judge beats
  instances stack            three Opus sessions

  Never set                  That replaces the writer you paid \$200 for
  ANTHROPIC_BASE_URL to      
  Ollama                     
  -----------------------------------------------------------------------

**4. Claude-native path (no Ollama)**

If you skip the local model, you can still keep most of the
architecture:

-   Deterministic PreToolUse command hooks for exact denials (secrets,
    rm -rf /, production deploys).

-   Prompt hooks on Haiku only for leftover semantic gates. Expect 1--3
    s and billed tokens.

-   Subagents with an explicit tier in CLAUDE.md (haiku = mechanical,
    sonnet = default, opus = design).

-   Custom compactPrompt plus a PreCompact checkpoint file so /compact
    does not drop file:line constraints.

-   Path-scoped CLAUDE.md and on-demand Skills instead of dumping every
    rule into every prompt.

Haiku is the cloud analogue of the local 7B. Use it when you are off the
laptop GPU, not as a second judge in series with Ollama.

**5. Local Ollama judge design**

**5.1 Request and response**

The hook never chats. It sends a tiny state and demands a flat JSON
object under Ollama structured outputs (format = JSON Schema,
temperature 0, stream false).

Required response shape:

*{ \"decision\": \"allow\" \| \"ask\" \| \"deny\", \"p\": 0.0-1.0 }*

Policy lives in the hook, not in the model:

-   Deterministic denylist matches → deny, no model call.

-   Deterministic allowlist matches (ls, git status, pytest in-repo) →
    allow, no model call.

-   Model deny and p ≥ 0.80 → deny.

-   Model allow and p ≥ 0.80 → allow.

-   Anything else, timeout, parse error, Ollama down → ask if the tool
    is Write/Edit/Bash with side effects, otherwise allow (fail open).

An 8B verbalized p is not Jev-calibrated. Treat it as a ranking score
and keep a wide ask band.

**5.2 What the live hook is allowed to score**

  -------------------------------------------------------------------------
  **Job**        **Hook**            **State sent**       **On 4070
                                                          laptop**
  -------------- ------------------- -------------------- -----------------
  Tool gate      PreToolUse          tool + command or    Primary job
                 Bash\|Write\|Edit   path + 2k cap        

  Rule picker    UserPromptSubmit    prompt + rule titles Optional; keep
                 (optional)          only                 under 2k

  Tier hint      UserPromptSubmit    last user turn only  Optional
                 (optional)                               

  Full-session   session.compact /   entire transcript    Do not. Heuristic
  compaction     huge state                               prune only
  -------------------------------------------------------------------------

**6. Guardrails**

**6.1 Safety guardrails**

-   PreToolUse fires even in dontAsk / \--dangerously-skip-permissions.
    Keep the denylist here so permission mode cannot bypass it.

-   Always deny writes to .env, id_rsa, credentials.json, and known
    secret filenames.

-   Always deny recursive deletes of / , \$HOME, system directories, and
    git clean -fdx without ask.

-   Always deny curl\|wget piped to a shell, and remote script
    execution.

-   Always deny git push \--force to main/master and force-push of tags
    unless the user typed that intent in the current prompt.

-   Hooks fail open on infrastructure errors so a dead Ollama does not
    freeze Claude Code. Safety still comes from the denylist, which does
    not need Ollama.

-   Log every decision (timestamp, tool, decision, p,
    source=rule\|model\|fallback, milliseconds) to
    \~/.claude/hooks/local-jev.log.

**6.2 RTX 4070 VRAM guardrails**

-   One model loaded. Never pull a second model "just in case" into the
    same Ollama process.

-   Context 4096. If nvidia-smi shows \> 7.2 GB allocated while
    idle-loaded, drop to 2048 or 3B.

-   Keep the model hot before the first Claude session (scripts do a
    one-token warmup).

-   Do not send file bodies, test output, or conversation history into
    the judge.

-   If hook p95 on the fixture exceeds 2000 ms warm, switch to
    llama3.2:3b.

**6.3 Max 20x quota guardrails**

-   Do not point Claude Code at Ollama. ANTHROPIC_BASE_URL stays on
    Anthropic.

-   Do not use Opus or Fable for routing, gating, or summarising tool
    traces.

-   Default writer: Sonnet. Escalate to Opus only for architecture,
    subtle bugs, or multi-file design.

-   Mechanical subagents (rename, generate fixtures, apply a known
    pattern) spawn as Haiku.

-   Avoid stacking extra Claude Code instances and long claude.ai chats
    on a heavy coding day.

-   Compact with a custom prompt that keeps paths, constraints, and
    decisions; do not pay a frontier model to re-summarise stale tool
    I/O.

-   Check /usage at the start of the day. If the weekly cap is yellow,
    lock writer to Sonnet and Haiku.

**7. Staging scripts**

Two scripts ship next to this document. They do the same work on each
OS.

  -------------------------------------------------------------------------
  **File**              **Platform**         **Role**
  --------------------- -------------------- ------------------------------
  stage-local-jev.ps1   Windows 10/11        Detect GPU, set Ollama env,
                        PowerShell 5+        pull model, install hook,
                                             merge settings, warmup,
                                             fixture

  stage-local-jev.sh    Linux bash           Same flow with systemd user
                                             unit hints and NVIDIA env
  -------------------------------------------------------------------------

**7.1 What the scripts install**

-   Ollama environment variables listed in section 3.1 (user-level,
    persistent).

-   \~/.claude/hooks/local_jev_gate.py --- cross-platform PreToolUse
    judge.

-   \~/.claude/hooks/local_jev_policy.json --- denylist / allowlist /
    thresholds you can edit without touching Python.

-   \~/.claude/hooks/compact-prompt.txt --- compactPrompt text that
    preserves constraints.

-   \~/.claude/local-jev.settings.json --- hook fragment. The script
    merges it into settings.json if possible; otherwise you paste it.

-   \~/.claude/CLAUDE-local-jev.md --- routing snippet to append to
    CLAUDE.md.

-   Fixture runner: six synthetic tool calls (ls, rm -rf /, .env write,
    git status, curl\|sh, ambiguous rm).

**7.2 How to run**

**Windows**

Open PowerShell as your normal user (not necessarily Administrator).
Execution policy for the current process only:

*Set-ExecutionPolicy -Scope Process Bypass; .\\stage-local-jev.ps1*

Optional flags: -Model qwen2.5:7b-instruct -SkipPull -DryRun

**Linux**

*chmod +x stage-local-jev.sh && ./stage-local-jev.sh*

Optional flags: \--model qwen2.5:7b-instruct \--skip-pull \--dry-run

The scripts never store Anthropic or TypeSafe API keys. They refuse to
set ANTHROPIC_BASE_URL.

**7.3 After staging**

-   Restart the Ollama service so environment variables load.

-   Restart Claude Code so hooks register. Confirm with /hooks.

-   Run a harmless command (ls) and a blocked pattern (write .env) and
    read \~/.claude/hooks/local-jev.log.

-   If Claude Code version is older than hook JSON permissionDecision
    support, the script still emits exit code 2 on deny for
    compatibility.

**8. Operating the system**

-   Tune thresholds in local_jev_policy.json. Do not re-prompt the 7B to
    "be more careful".

-   Once a week, sample the log. Count false denies (annoyance) vs false
    allows that the denylist should have caught (bugs).

-   When you add a new exact rule, add it to the JSON policy. Do not
    grow the model prompt.

-   If you later want Jev-shaped probabilities, keep the same hook and
    point it at a local System One server (Kev + Ollama, or a dedicated
    decision head). Do not rebuild Claude Code.

-   Upgrade path if 7B quality is weak on your repo dialect: collect 200
    labelled tool calls from the log, then consider a small classifier
    --- still local, still not Jev.

**9. What this will not do**

-   It will not match hosted Jev at 70--500 ms with calibrated
    confidence.

-   It will not let you auto-approve destructive Bash unsupervised. The
    ask band exists on purpose.

-   It will not run Jev-style "score every historical tool row"
    compaction on 8 GB.

-   It will not turn qwen2.5:7b into a replacement for Sonnet on Max
    20x.

-   It will not make Max 20x unlimited. It only stops spending that cap
    on questions a 7B can answer.

**10. Recommended daily profile**

  -----------------------------------------------------------------------
  **Work**                **Model**             **Why**
  ----------------------- --------------------- -------------------------
  Implement / edit / test Sonnet                Best default on Max 20x
  in-repo                                       

  Architecture, gnarly    Opus (or Fable if you Spend quota where writing
  bug, multi-module       accept the 50% weekly quality matters
  design                  cap)                  

  Rename, boilerplate,    Haiku subagent        Cheap writer, not a judge
  apply a known pattern                         

  Allow / ask / deny tool Local 7B via hook     Zero Anthropic tokens
  calls                                         

  Exact policy            Code                  Zero models
  -----------------------------------------------------------------------

**11. File map**

  --------------------------------------------------------------------------------
  **Path**                                       **Created by**
  ---------------------------------------------- ---------------------------------
  Jev-Engineering-Local-Claude-Code-Guide.docx   This document

  stage-local-jev.ps1                            Windows staging

  stage-local-jev.sh                             Linux staging

  \~/.claude/hooks/local_jev_gate.py             Both scripts

  \~/.claude/hooks/local_jev_policy.json         Both scripts

  \~/.claude/hooks/local-jev.log                 Hook at runtime

  \~/.claude/local-jev.settings.json             Both scripts
  --------------------------------------------------------------------------------

**12. Bottom line**

Keep the \$200 writer. Put an 8 GB-safe local judge in front of tool
calls. Enforce secrets and destruction in code. Fail open on
infrastructure. Fail closed on the denylist. That is the entire
replacement for Jev Engineering on this laptop.

Staging is complete when /hooks lists the gate, nvidia-smi shows one 7B
resident under 7 GB, the fixture denies rm -rf / and .env writes without
calling the model, and a warm allow for ls returns in under two seconds.
