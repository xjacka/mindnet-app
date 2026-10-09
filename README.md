# MindNet

Vhoď článek, který nemáš čas přečíst. Rozpadne se na pár krátkých příspěvků —
ve tvém jazyce a podle toho, co tě zajímá.

**Veřejná beta.** Web s návodem: **https://xjacka.github.io/mindnet-app/**

Tohle repo slouží k distribuci: najdeš tu instalační soubory, návod
a skill pro vlastního agenta. Zdrojový kód appky tu není.

## Stažení

| | |
|---|---|
| Android | [mindnet.apk](https://github.com/xjacka/mindnet-app/releases/latest/download/mindnet.apk) |
| Rozšíření pro Chrome | [mindnet-extension.zip](https://github.com/xjacka/mindnet-app/releases/latest/download/mindnet-extension.zip) |

Odkazy vedou vždycky na poslední vydání. Starší verze jsou v
[Releases](https://github.com/xjacka/mindnet-app/releases).

### Android

1. Stáhni APK v telefonu a otevři ho.
2. Povol prohlížeči instalovat aplikace (*Instalovat neznámé aplikace*).
3. Když se ozve Google Play Protect, zvol *Další podrobnosti → Přesto
   nainstalovat*. MindNet zatím není v Google Play.

Na novou verzi upozorní appka sama. Instaluje se přes starou verzi a nic
se při tom neztratí.

### Rozšíření pro Chrome

1. Rozbal zip tam, kde může složka `mindnet-extension` natrvalo zůstat.
2. `chrome://extensions` → zapni **Režim pro vývojáře** → **Načíst
   rozbalené** → vyber složku `mindnet-extension`.
3. Otevři rozšíření a přes ⚙ se přihlas stejným účtem jako v appce.

Na novou verzi upozorní štítek *Nová verze* v okně rozšíření. Nový zip
rozbal přes starou složku a v `chrome://extensions` rozšíření obnov.

## Vlastní agent

Máš-li vlastní předplatné (třeba Claude), může tvoje články zpracovávat
tvůj agent. V appce v nastavení účtu → *Vlastní agent* vytvoříš klíč
a dostaneš příkaz pro Claude Code. Agent pak potřebuje skill
[`skills/zpracuj-clanky`](skills/zpracuj-clanky), který popisuje celý
postup.

Soubory `references/supabase.md`, `scripts/ceka-prace.sh`
a `scripts/test-vyzvednuti.sh` patří systémovému agentovi provozovatele
a vlastní agent je nepotřebuje.

## Soukromí a podmínky

- [Zásady ochrany soukromí](https://xjacka.github.io/mindnet-app/privacy.html)
- [Podmínky bety](https://xjacka.github.io/mindnet-app/#podminky)

## Kontakt

Chyby a nápady do [issues](https://github.com/xjacka/mindnet-app/issues)
nebo na xjacka@gmail.com.
