# MindNet

**[English](#english) · [Česky](#česky)**

Website: **https://xjacka.github.io/mindnet-app/** ([English](https://xjacka.github.io/mindnet-app/en/))

| | |
|---|---|
| Android | [mindnet.apk](https://github.com/xjacka/mindnet-app/releases/latest/download/mindnet.apk) |
| Chrome extension | [mindnet-extension.zip](https://github.com/xjacka/mindnet-app/releases/latest/download/mindnet-extension.zip) |
| Web app | [xjacka.github.io/mindnet-app/app/](https://xjacka.github.io/mindnet-app/app/) |

---

## English

Drop in an article you have no time to read. It breaks down into a few
short posts — in your language and shaped by what interests you.

**Public beta.** This repository is for distribution: the installation
files, the guide and the skill for your own agent. The app's source code
is not here. The links above always point to the latest release; older
versions are under [Releases](https://github.com/xjacka/mindnet-app/releases).

### Android

1. Download the APK on your phone and open it.
2. Allow your browser to install apps (*Install unknown apps*).
3. If Google Play Protect warns you, choose *More details → Install
   anyway*. MindNet is not on Google Play yet.

The app announces new versions itself. Install them over the old one;
nothing gets lost.

### Web app

The same app in your browser, nothing to install:
**https://xjacka.github.io/mindnet-app/app/**. Sign in with the same
account as on your phone. Notifications and sharing into the app are
Android only.

### Chrome extension

1. Unpack the zip somewhere the `mindnet-extension` folder can stay for good.
2. `chrome://extensions` → switch on **Developer mode** → **Load
   unpacked** → pick the `mindnet-extension` folder.
3. Open the extension and sign in via ⚙ with the same account as in the app.

A *New version* label in the extension window announces updates. Unpack
the new zip over the old folder and reload the extension in
`chrome://extensions`.

### Your own agent

If you have your own subscription (Claude, for example), your own agent
can process your articles. In the app, account settings → *Your own
agent* creates a key and shows a command that installs the MindNet plugin
for Claude Code with that key. By hand, in Claude Code:

```
/plugin marketplace add xjacka/mindnet-app
/plugin install mindnet@mindnet-app
/mindnet:setup
```

The plugin ([`plugins/mindnet`](plugins/mindnet)) brings the MindNet MCP
server, the skill
[`process-mindnet-articles`](plugins/mindnet/skills/process-mindnet-articles)
and `/mindnet:setup`, which checks the connection and sets up regular
runs. Other agents (Codex CLI, Cursor…) add an HTTP MCP server with the
address from the app and the header `Authorization: Bearer mn_agent_…`
and use the same skill.

### Privacy and terms

- [Privacy policy](https://xjacka.github.io/mindnet-app/en/privacy.html)
- [Beta terms](https://xjacka.github.io/mindnet-app/en/#terms)

### Contact

Bugs and ideas: [issues](https://github.com/xjacka/mindnet-app/issues)
or app.mindnet@gmail.com.

---

## Česky

Vhoď článek, který nemáš čas přečíst. Rozpadne se na pár krátkých
příspěvků — ve tvém jazyce a podle toho, co tě zajímá.

**Veřejná beta.** Tohle repo slouží k distribuci: najdeš tu instalační
soubory, návod a skill pro vlastního agenta. Zdrojový kód appky tu není.
Odkazy nahoře vedou vždycky na poslední vydání; starší verze jsou
v [Releases](https://github.com/xjacka/mindnet-app/releases).

### Android

1. Stáhni APK v telefonu a otevři ho.
2. Povol prohlížeči instalovat aplikace (*Instalovat neznámé aplikace*).
3. Když se ozve Google Play Protect, zvol *Další podrobnosti → Přesto
   nainstalovat*. MindNet zatím není v Google Play.

Na novou verzi upozorní appka sama. Instaluje se přes starou verzi a nic
se při tom neztratí.

### Web

Tatáž appka v prohlížeči, bez instalace:
**https://xjacka.github.io/mindnet-app/app/**. Přihlas se stejným účtem
jako v telefonu. Notifikace a sdílení do appky umí jen Android.

### Rozšíření pro Chrome

1. Rozbal zip tam, kde může složka `mindnet-extension` natrvalo zůstat.
2. `chrome://extensions` → zapni **Režim pro vývojáře** → **Načíst
   rozbalené** → vyber složku `mindnet-extension`.
3. Otevři rozšíření a přes ⚙ se přihlas stejným účtem jako v appce.

Na novou verzi upozorní štítek *Nová verze* v okně rozšíření. Nový zip
rozbal přes starou složku a v `chrome://extensions` rozšíření obnov.

### Vlastní agent

Máš-li vlastní předplatné (třeba Claude), může tvoje články zpracovávat
tvůj agent. V appce v nastavení účtu → *Vlastní agent* vytvoříš klíč
a dostaneš příkaz, který plugin MindNet do Claude Code nainstaluje rovnou
s tím klíčem. Ručně v Claude Code:

```
/plugin marketplace add xjacka/mindnet-app
/plugin install mindnet@mindnet-app
/mindnet:setup
```

Plugin ([`plugins/mindnet`](plugins/mindnet)) přinese MCP server MindNetu,
skill [`process-mindnet-articles`](plugins/mindnet/skills/process-mindnet-articles)
a `/mindnet:setup`, který ověří připojení a nastaví pravidelné běhy. Jiní
agenti (Codex CLI, Cursor…) přidají HTTP MCP server s adresou z appky
a hlavičkou `Authorization: Bearer mn_agent_…` a použijí týž skill.

### Soukromí a podmínky

- [Zásady ochrany soukromí](https://xjacka.github.io/mindnet-app/privacy.html)
- [Podmínky bety](https://xjacka.github.io/mindnet-app/#podminky)

### Kontakt

Chyby a nápady do [issues](https://github.com/xjacka/mindnet-app/issues)
nebo na app.mindnet@gmail.com.
