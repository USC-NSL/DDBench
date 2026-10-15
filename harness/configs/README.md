# mini-swe-agent configurations

YAML configs for [mini-swe-agent](https://mini-swe-agent.com/) (pinned to
v2.2.8 by `addons/examples/mini-swe-agent.sh`), the agent used by
`harness/run_agent.sh`.

| Config | Condition | Tool-call style |
|--------|-----------|-----------------|
| `ddbench_prompt.yaml` | repo-only (default) | native tool calling (`bash` tool) |
| `ddbench_prompt_context.yaml` | context-augmented (`--context`) | native tool calling |
| `ddbench_prompt_textbased.yaml` | repo-only | text-based: one fenced `mswea_bash_command` block per turn, for models without native tool calling |
| `ddbench_prompt_context_textbased.yaml` | context-augmented | text-based |

`run_agent.sh` picks `ddbench_prompt.yaml`, or `ddbench_prompt_context.yaml`
with `--context`; pass `--config <file>` to use another one.

## What the configs set

- **Task prompt.** The agent is told to read `SYMPTOM.md` (and, in the context
  condition, `context/`), find the root cause, and fix it by editing the source
  in place. It must keep `./REBUILD.sh` passing. It may use the internet for
  documentation, but must not search for the upstream issue, pull request, or
  fix, and must not look at commits after the buggy one. The worktree only
  contains history up to the buggy commit, so there are none to look at.
- **Budgets.** `step_limit: 400` and `cost_limit` (30 USD for the native
  configs, 50 USD for the text-based ones). `run_agent.sh --timeout` adds a
  wall-clock limit per case (default 1800 s).
- **Execution.** Each command has a 300 s timeout
  (`environment.timeout`). Pagers are disabled. Outputs longer than 10,000
  characters are elided to their head and tail.
- **Model.** `model_class: litellm` with `temperature: 0.0`. The model name
  is NOT set in the configs: it comes from `MSWEA_MODEL_NAME` or
  `run_agent.sh --model`, and there is no default (to avoid accidental API
  spend). Any [litellm](https://docs.litellm.ai/docs/providers) model name
  works, e.g. `anthropic/claude-sonnet-4-20250514`, `openai/gpt-4o`,
  `gemini/gemini-2.5-pro`. Provider keys (`ANTHROPIC_API_KEY`,
  `OPENAI_API_KEY`, ...) are forwarded into the agent container by
  `bench.sh`.
- **Provider endpoint.** `model.model_kwargs` contains commented examples of
  provider/endpoint settings (`custom_llm_provider`, `api_base`). Set
  `api_base` only if you route requests through your own gateway. Otherwise,
  remove it so that litellm uses the provider's public endpoint. If the gateway
  listens on the host's localhost, run with `run_agent.sh --host-network`.

The configs are merged on top of mini-swe-agent's default `mini.yaml`
(`bench.sh agent` passes `--config mini.yaml --config <this file>`), so they
must not set `model_name`, `environment_class`, or `cwd`.

## Usage

```bash
# one case, repo-only condition
MSWEA_MODEL_NAME=anthropic/claude-sonnet-4-20250514 \
  harness/run_agent.sh raft-358-negative-log-range

# a whole tier, context-augmented condition
harness/run_agent.sh --surface tier1 --model openai/gpt-4o --context

# a custom config
harness/run_agent.sh --surface tier1 --config harness/configs/ddbench_prompt_textbased.yaml

# show the per-case steps without running anything
harness/run_agent.sh --surface tier1 --dry-run
```

Set `DDBENCH_CONFIG_DIR` to make `run_agent.sh` read its default configs from
another directory.
