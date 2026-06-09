# RT-Extension-Redesign

Modernes UI-Redesign für Request Tracker 6 — globales CSS-Overhaul und modernisierte Templates für alle wichtigen RT-Seiten.

![Login Screen](docs/login-screen.png)

## Features

### Login-Seite
Zweispaltiges Layout:
- **Links (75%):** Plugin-Inhalte (BeforeForm-Callbacks) + Live-Systemstatistiken mit 6-Stunden-Cache
- **Rechts (25%, dunkelblau):** RT-Logo, Instanzname, Slogan, Login-Formular

Die Systemstatistiken zeigen: Privilegierte/unprivilegierte Benutzer, Gruppen, Queues, Tickets, Transaktionen, Assets und Artikel — mit formatierter Ausgabe (deutsche Tausendertrennzeichen).

### Globales Styling
- TitleBox: abgerundete Ecken, Schatten
- Tabellen, History, Pagination, Search Builder
- Ticket-Liste: kompakter Header, Filter-Buttons, Priorität-Farben
- Ticket-Detail: Section-Icons, Feldlabels uppercase
- Dashboard: Portlet-Icons, Ergebnis-Banner
- History: farbige Randbalken je Typ
- Reply/Comment: blauer/oranger Randbalken
- Dark Mode Unterstützung via `var(--bs-*)` CSS-Variablen

### Weitere Seiten
- `/Admin/` — Stat-Karten, Info-Karten, Menu-Kacheln
- `/Reports/` — Card-Grid
- `/Tools/index.html` — Stat-Karten und Navigations-Kacheln
- `/Search/Simple.html` — Hero-Suche mit Keyword-Karten

## Replaces RT-Extension-AdminDashboard

> **If you have RT-Extension-AdminDashboard installed, remove it before or after
> installing this extension — the two should not be active at the same time.**

This extension fully absorbs everything that was previously provided by
**RT-Extension-AdminDashboard** (archived as of v0.07). You do not need that
extension anymore. All its functionality is built in here:

| AdminDashboard feature | Where it lives now |
|---|---|
| `collect_stats()` — cached system statistics | `lib/RT/Extension/Redesign.pm` |
| `bin/rt-admin-dashboard-refresh` cron script | `bin/rt-redesign-stats-refresh` |
| Admin portal stat cards and info cards | `html/Admin/index.html` |
| Global scrips/templates dashboard | `html/Admin/Global/index.html` |
| Sub-section dashboards (Articles, Assets, Tools, CustomFields) | `html/Admin/*/index.html` |
| Shared dashboard CSS/JS components | `html/Admin/Elements/AdminDashboardCSS` / `AdminDashboardJS` |
| Maintenance/welcome banner admin page | `html/Admin/Global/LoginBanner.html` |
| "Login Banner" menu entry under Admin → Global | `html/Callbacks/Redesign/Elements/Header/PrivilegedMainNav` |
| Login page banner (bilingual DE/EN) | `html/Callbacks/Redesign/Elements/Login/BeforeForm` |

**To migrate from RT-Extension-AdminDashboard:**

1. Install this extension (`perl Makefile.PL && make && sudo make install`).
2. Remove `Plugin('RT::Extension::AdminDashboard');` from your `RT_SiteConfig.pm`.
3. Replace any cron entry that calls `rt-admin-dashboard-refresh` with
   `rt-redesign-stats-refresh` — the attribute name (`AdminDashboardStats`) and
   all behaviour remain identical.
4. Clear the Mason cache and restart Apache.

## Installation

```bash
perl Makefile.PL
make
sudo make install
```

Plugin in `RT_SiteConfig.pm` registrieren:

```perl
Plugin('RT::Extension::Redesign');
```

Mason-Cache leeren und Apache neu starten:

```bash
sudo systemctl stop apache2
sudo rm -rf /opt/rt6/var/mason_data/obj/*
sudo systemctl start apache2
```

## Anforderungen

- Request Tracker 5.0 oder höher
- RT 7.0 nicht unterstützt

## Autor

Torsten Brumm

## Lizenz

GNU General Public License v2
