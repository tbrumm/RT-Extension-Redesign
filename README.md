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
