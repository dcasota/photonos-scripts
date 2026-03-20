# ADR-0002: xAI/Grok API for Blog Post Generation

**Date:** 2026-03-21

**Status:** Accepted

## Context

The documentation system must generate structured monthly changelogs from raw git
commits stored in SQLite. These changelogs are published as Hugo-compatible markdown
blog posts on the Photon OS documentation site. Key requirements:

- **Volume:** Approximately 360 blog posts must be generated across 6 branches
  (1.0 through 5.0 and dev) spanning roughly 5 years of monthly history.
- **Quality:** Output must be technically accurate and detailed enough to be useful
  to downstream consumers (security teams, release engineers, package maintainers).
- **Format:** Each post must follow the Keep-a-Changelog structure with categorized
  sections (Security, Updated, Added, Removed, Fixed) and Hugo front matter.
- **Reproducibility:** Re-running the summarizer for an already-generated month
  must not duplicate work or produce inconsistent results.

## Decision

Use the **xAI Grok API** (model `grok-4-0709`) with structured prompts that enforce
the Keep-a-Changelog output format. The summarizer:

1. Queries the SQLite database for all commits in a given branch/month window.
2. Constructs a prompt with commit data and explicit formatting instructions.
3. Sends the prompt to the Grok API and receives structured markdown.
4. Stores the result in the `summaries` table with metadata (model name, timestamp).
5. Writes the Hugo-compatible `.md` file to the content directory.

Idempotency is achieved by checking the `summaries` table before making an API call.
If a summary already exists for a given `(branch, year, month)` tuple, the API call
is skipped entirely.

All generated posts include an AI disclaimer footer acknowledging automated generation.

## Alternatives Considered

### Alternative 1: Ollama Local LLM

Run a local large language model (e.g., Llama 3, Mistral) via Ollama to avoid
external API dependencies entirely.

- **Rejected because:** Insufficient output quality for technical changelog
  summarization — local models frequently hallucinate package names and version
  numbers. Inference is prohibitively slow on CPU-only build hosts (~5 minutes
  per summary vs. ~10 seconds via API). Generating 360 posts would take days.

### Alternative 2: OpenAI GPT-4

Use the OpenAI API with GPT-4 or GPT-4-turbo for summarization.

- **Viable alternative** but rejected for this project because: Higher cost per
  token with no significant quality advantage for structured changelog generation.
  The Grok model performs comparably on this specific task at lower cost. Could
  be reconsidered if xAI API availability becomes unreliable.

### Alternative 3: Manual Authoring

Have a human author write all 360+ monthly blog posts by reading commit logs.

- **Rejected because:** Completely infeasible at this scale. At an optimistic
  15 minutes per post, manual authoring would require 90+ hours of focused
  writing. The output would still be less consistent in format and categorization
  than LLM-generated content with structured prompts.

## Consequences

- **API key requirement:** The `XAI_API_KEY` environment variable must be set
  before running the summarizer. The tool fails fast with a clear error if the
  key is missing.
- **Rate limiting:** API calls are rate-limited with configurable delays between
  requests to avoid hitting xAI rate limits. Default is 2 seconds between calls.
- **Resumable processing:** Database-backed idempotency means the summarizer can
  be interrupted and restarted without re-processing completed months. This is
  critical for a 360-post batch that may span multiple sessions.
- **AI disclaimer:** Every generated post includes a footer noting it was
  AI-generated. This maintains transparency and sets reader expectations about
  potential inaccuracies.
- **Cost:** Estimated total cost for 360 posts is approximately $15-25 USD at
  current xAI pricing, which is negligible compared to manual authoring effort.
- **Vendor dependency:** The system depends on xAI API availability. If the API
  is deprecated or becomes unavailable, the prompt templates can be adapted to
  an alternative LLM provider with minimal code changes.
