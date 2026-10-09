---
description: Check the MindNet connection and set up, change or remove the regular processing of your articles
argument-hint: "[15m | 30m | 1h | off]"
---

# MindNet setup

The person wants their MindNet articles processed by this agent. Talk to
them in their language (Czech when they write Czech). Go step by step and
stop where a step fails — say what to fix and how.

Argument: `$ARGUMENTS` — an interval (`15m`, `30m`, `1h`) or `off`. Empty →
ask.

## 1. The connection

Call the `status` tool of the MindNet MCP server (this plugin's server
`mindnet`; the tool is named like `mcp__plugin_mindnet_mindnet__status`).

- **The tool is not there** → the plugin was installed after this session
  started. Tell them to run `/reload-plugins` (or restart Claude Code) and
  then `/mindnet:setup` again. Stop.
- **The server rejects the key** (401, „invalid key“, the server fails to
  connect) → the key is wrong or was revoked. They create a new one in the
  MindNet app (Profile → *Vlastní agent* → *Vytvořit klíč*; in English
  *Your own agent* → *Create a key*) and set it with
  `/plugin configure mindnet@mindnet-app`; then `/reload-plugins` and
  `/mindnet:setup` again. Stop.
- **It answers** → say in one or two sentences what waits (`waiting`,
  `articles`) and what is in progress.

Then remind them of the one setting only the app can make: in the
profile, *Zpracování obsahu → Kdo zpracuje moje články* (in English *How
your content is processed → Who processes my articles*), they choose
**Vlastní agent** (*Your own agent*). Without it the requests go to the
API model and the queue here stays empty.

## 2. Is a schedule wanted?

Explain in two sentences: without a schedule the articles are processed
when they ask („zpracuj moje články“); with one, the agent checks the
queue every N minutes, and a check with nothing waiting is one short call.
When the agent does not answer within the deadline (`answer_within_min`
from `status`), the API model takes the article over, so nothing gets
stuck when the computer is off.

When the argument is empty, ask: every 15 minutes, 30 minutes
(recommended), an hour, or no schedule. `off` → step 5.

## 3. Where the schedule runs

Look for an existing MindNet schedule first (step 5 lists where) and
change it instead of adding a second one. Then pick by what you have:

**a) The Claude desktop app** — the tool `create_scheduled_task` (server
`scheduled-tasks`) is among your tools. Recommended: it survives
restarts, and a run missed while the app was closed runs on the next
launch.
Create the task with:
- `taskId`: `mindnet-articles`, `title`: „MindNet – zpracování článků“
  (in the person's language);
- `cronExpression`: `*/15 * * * *`, `*/30 * * * *` or `0 * * * *`;
- `description`: „Processes waiting MindNet articles“;
- `notifyOnCompletion`: `false` (most runs find nothing);
- `prompt`: the scheduled prompt below, verbatim.

Say that it runs while the desktop app is open.

**b) A terminal session only** — offer the two choices and let them pick:

1. **`/loop`, for this session only.** They type it themselves:
   ```
   /loop 30m <the scheduled prompt>
   ```
   It ends when the session ends.
2. **A background job that survives restarts**, through `claude -p`.
   Show the job and its command line before you write anything, and write
   it only after a clear yes. Resolve the absolute path of `claude`
   (`command -v claude`) and put it in; a job does not get the shell's
   PATH.
   - **macOS** — a LaunchAgent `~/Library/LaunchAgents/app.mindnet.agent.plist`
     with `Label` `app.mindnet.agent`, `StartInterval` in seconds (900,
     1800, 3600), `ProgramArguments` = the command below split into
     arguments, `StandardOutPath` and `StandardErrorPath`
     `~/Library/Logs/mindnet-agent.log` (absolute paths), and
     `WorkingDirectory` the home directory. Load it with
     `launchctl bootstrap gui/$(id -u) <plist>`. A LaunchAgent runs in the
     logged-in session, so the keychain with the Claude login and the
     plugin key is unlocked; cron on macOS does not have that.
   - **Linux** — one crontab line ending in `# mindnet`, added with
     `(crontab -l 2>/dev/null | grep -v '# mindnet$'; echo '<line>') | crontab -`;
     output appended to `~/.mindnet-agent.log`.

   The command (one run):
   ```
   <claude> -p --allowedTools "mcp__plugin_mindnet_mindnet" "Bash(sleep *)" "Bash(grep *)" -- "<the scheduled prompt>"
   ```
   `--allowedTools` lets the unattended run use the MindNet tools and the
   two shell commands the skill uses (waiting a minute, searching the
   article) without a prompt nobody would answer.

## 4. Permissions for unattended runs

A scheduled task in the desktop app and a `/loop` run with the person's
permission settings: a tool that asks for permission waits until someone
answers. Offer to add to the `permissions.allow` list in
`~/.claude/settings.json`:

```json
"mcp__plugin_mindnet_mindnet", "Bash(sleep *)", "Bash(grep *)"
```

Show the change, edit only after a yes, keep everything else in the file.
The background job of 3b) does not need this; it has `--allowedTools`.

## 5. Change or remove

`off`, or the person wants the schedule gone or different: find it and
remove or change it, and say what you did.
- desktop app: `list_scheduled_tasks` → `mindnet-articles` →
  `update_scheduled_task` (other interval, or disable);
- macOS: `launchctl bootout gui/$(id -u)/app.mindnet.agent` and delete the
  plist;
- Linux: `(crontab -l | grep -v '# mindnet$') | crontab -`;
- `/loop`: it ends with the session; they can stop it with Esc.

## 6. The end

Two or three sentences: what waits, whether and how often it runs, where
to change it (`/mindnet:setup` again). Offer to process what waits right
now.

## The scheduled prompt

Use it word for word in every kind of schedule:

```
MindNet scheduled run. Call the status tool of the MindNet MCP server (plugin mindnet). If waiting is empty, reply with one line that nothing waits and stop — load nothing else. Otherwise process the waiting articles with the skill mindnet:process-mindnet-articles as a scheduled run.
```
