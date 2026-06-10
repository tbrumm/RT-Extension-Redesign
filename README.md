# RT-Extension-Redesign

Modernes UI-Redesign für Request Tracker 6 — globales CSS-Overhaul, modernisierte Templates und eine wachsende Sammlung integrierter Erweiterungen für Dashboard-Widgets, Ticket-Widgets und UI-Verbesserungen.

![Login Screen](docs/login-screen.png)

---

## Inhalt

- [Features](#features)
  - [Globales Styling](#globales-styling)
  - [Seiten-Templates](#seiten-templates)
  - [Ticket-Seiten-Widgets](#ticket-seiten-widgets)
  - [Dashboard-Widgets](#dashboard-widgets)
  - [Syntax-Highlighting](#syntax-highlighting)
- [Konfiguration](#konfiguration)
- [Installation](#installation)
- [Integrierte Erweiterungen](#integrierte-erweiterungen)
- [Anforderungen](#anforderungen)
- [Autor / Lizenz](#autor--lizenz)

---

## Features

### Globales Styling

Das Extension überlagert RT6 mit einem modernen CSS-Overhaul auf Basis von Bootstrap 5.3 und Bootstrap Icons:

- **TitleBox:** abgerundete Ecken, dezente Schatten, farbige obere Randbalken je Widget-Typ
- **Tabellen:** kompakte Header, Filter-Buttons, Priority-Badges (grün/gelb/rot), SLA-Badges
- **Ticket-Liste:** Priority und SLA als farbige Badges, Due-Date-Badges, Status-Badges
- **Ticket-Detail:** Section-Icons (Bootstrap Icons), Feldlabels uppercase, farbige Randbalken je History-Typ
- **Dashboard:** Portlet-Icons, Ergebnis-Banner, kompakte Portlet-Header
- **Reply/Comment:** blauer/oranger Randbalken zur visuellen Unterscheidung
- **Dark Mode:** vollständig unterstützt via `var(--bs-*)` CSS-Variablen und `[data-bs-theme=dark]`-Selektoren

### Seiten-Templates

Überschriebene RT-Seiten mit modernem Layout:

| Seite | Was sich ändert |
|---|---|
| **Login** (`/`) | Zweispaltiges Layout — links Plugin-Inhalte + Live-Systemstatistiken, rechts Login-Formular |
| **Admin** (`/Admin/`) | Stat-Karten, Info-Karten, Navigations-Kacheln statt bestpractical.com-iframe |
| **Admin → Global** | Scrips/Templates-Dashboard mit Zählern |
| **Admin → Articles/Assets/Tools/CustomFields** | Übersichts-Dashboards mit Karten |
| **Admin → Global → Login Banner** | Bearbeitungsseite für das Login-Banner |
| **Reports** (`/Reports/`) | Card-Grid mit Report-Kacheln |
| **Tools** (`/Tools/`) | Stat-Karten und Navigations-Kacheln |
| **Simple Search** (`/Search/Simple.html`) | Hero-Suche mit Keyword-Karten |

Die **Systemstatistiken** auf der Login-Seite zeigen: privilegierte/unprivilegierte Benutzer, Gruppen, Queues, Tickets, Transaktionen, Assets und Artikel — mit 6-Stunden-Cache via `rt-redesign-stats-refresh`.

### Ticket-Seiten-Widgets

Diese Widgets können über **Admin → Global → Page Layouts** zu Ticket-Spalten hinzugefügt werden:

#### DisplaySLA

Zeigt SLA-Level und beide Fristen (Time to React + Time to Resolve) farbcodiert an:

- **Grün** → ausreichend Zeit verbleibend
- **Gelb** → weniger als 25 % der Gesamtzeit verbleibend
- **Rot** → Frist überschritten
- **Pause-Anzeige** → wenn das Ticket in einem ignorierten Status ist

Das Widget blendet sich automatisch aus, wenn für die Queue kein SLA konfiguriert ist.

#### LifecycleWidget

Stellt den Lifecycle der Ticket-Queue als interaktives SVG-Diagramm dar:

- Status-Knoten farbcodiert nach Typ (Initial / Active / Inactive)
- Aktueller Status des Tickets hervorgehoben
- Übergangspfeile zwischen Statuses
- Adaptives Layout: passt sich der Widget-Breite an (responsiv)
- Bei komplexen Lifecycles (> 20 Statuses): zeigt nur Übergänge vom/zum aktuellen Status

#### LinkedArticles

Zeigt alle mit dem Ticket verknüpften Artikel als kompakte Karten:

- Artikel-Name als Link, Klasse als Badge
- Zusammenfassung (falls vorhanden)
- Aktualisiert sich automatisch via HTMX wenn Links geändert werden
- Blendet sich aus wenn keine Artikel verknüpft sind

### Dashboard-Widgets

Diese Widgets können als Portlets zum RT-Dashboard hinzugefügt werden. Portlet-Namen für `$HomepageComponents` sind in Klammern angegeben.

#### ClockWidget (`ClockWidget`)

Animierte Flip-Clock im Apple-Stil — zeigt Uhrzeit (Stunden/Minuten) und Datum in der lokalen Zeitzone des Browsers.

#### WeatherWidget (`WeatherWidget`)

Live-Wetterdaten aus dem Nutzerprofil:

- Bezieht Standort aus **City**, **Zip** und **Country** des RT-Nutzerprofils
- Geocoding via Open-Meteo + Nominatim (kein API-Key erforderlich)
- Zeigt: Temperatur, Wetterbedingung, gefühlte Temperatur, Wind, Luftfeuchtigkeit
- Session-Cache (30 Minuten), Retry-Button, Dark-Mode-Unterstützung
- Konfigurierbare Temperatureinheit (`celsius` / `fahrenheit`)

Wenn kein Standort im Profil hinterlegt ist, wird ein Link zu den Einstellungen angezeigt.

#### FeedWidget (`FeedWidget`)

RSS/ATOM-Feed-Reader mit Tabs — vollständig per Nutzer konfigurierbar:

- Feeds werden in **Prefs → About Me** konfiguriert (URL, Bezeichnung, max. Einträge)
- Für jeden Feed ein Tab mit Titel, Datum und Zusammenfassung der Einträge
- Feed-Abruf serverseitig (kein CORS-Problem)
- Session-Cache (15 Minuten), Refresh-Button
- Erfordert CSRF-Whitelist (siehe [Konfiguration](#konfiguration))

#### UserProfileWidget (`UserProfileWidget`)

Profilkarte des eingeloggten Nutzers:

- Avatar (aus RT-Profil), Name, Organisation
- E-Mail, Telefon (Arbeit + Mobil), Adresse
- Link zu **Prefs → About Me** zum direkten Bearbeiten

#### ArticlesWidget (`ArticlesWidget`)

Zeigt die 5 neuesten Artikel aller zugänglichen Klassen als kompakte Karten — mit Name, Klasse, Zusammenfassung, Autor und Alter.

#### AssetsWidget (`AssetsWidget`)

Zeigt die 5 zuletzt aktualisierten Assets als kompakte Karten — mit ID, Name, Katalog, Status, Halter und letzter Aktualisierung.

### Syntax-Highlighting

Fügt Syntax-Highlighting zu CKEditor-Code-Blöcken in Ticket-Beschreibungen und -Antworten hinzu:

- Bibliothek: [highlight.js](https://highlightjs.org/) (Standard: v11.10.0 via CDN)
- Synchronisiert sich mit dem RT Dark/Light-Mode
- Unterstützte Sprachen: Perl, JavaScript, Python, Bash, SQL, YAML, JSON, XML/HTML, Plain Text
- Sprachauswahl im CKEditor-Toolbar konfigurierbar (siehe [Konfiguration](#konfiguration))

---

## Konfiguration

### FeedWidget — CSRF-Whitelist

FeedWidget nutzt interne Helfer-Endpunkte, die in `RT_SiteConfig.pm` freigeschaltet werden müssen:

```perl
Set(%ReferrerComponents,
    "/FeedWidget/Fetch.html"     => 1,
    "/FeedWidget/SaveFeeds.html" => 1,
);
```

### WeatherWidget — Temperatureinheit

```perl
Set(%WeatherWidgetOptions,
    TemperatureUnit => 'celsius',   # oder 'fahrenheit'
);
```

### DisplaySLA — Level-Farben

Optionale Farb-Überschreibung für SLA-Level-Badges (Standard-Farben sind eingebaut):

```perl
Set(%DisplaySLAOptions,
    LevelColors => {
        kritisch => '#dc3545',
        hoch     => '#fd7e14',
        normal   => '#0d6efd',
        niedrig  => '#198754',
    },
);
```

### Syntax-Highlighting — CDN-URLs

```perl
# highlight.js CDN (leer lassen = deaktiviert)
Set($SyntaxHighlightJS,
    'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.10.0/highlight.min.js');

# Light-Mode Theme
Set($SyntaxHighlightCSS,
    'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.10.0/styles/github.min.css');

# Dark-Mode Theme
Set($SyntaxHighlightCSSdark,
    'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.10.0/styles/github-dark.min.css');
```

### CKEditor-Sprachauswahl für Code-Blöcke

```perl
Set(%MessageBoxRichTextInitArguments,
    codeBlock => {
        languages => [
            { language => 'plaintext',   label => 'Plain text'  },
            { language => 'perl',        label => 'Perl'        },
            { language => 'javascript',  label => 'JavaScript'  },
            { language => 'python',      label => 'Python'      },
            { language => 'bash',        label => 'Bash/Shell'  },
            { language => 'sql',         label => 'SQL'         },
            { language => 'yaml',        label => 'YAML'        },
            { language => 'json',        label => 'JSON'        },
            { language => 'xml',         label => 'XML/HTML'    },
        ],
    },
);
```

### Dashboard-Widgets — HomepageComponents

Damit die neuen Portlets im Dashboard-Editor erscheinen:

```perl
Set($HomepageComponents, [qw(
    QuickCreate Quicksearch MyAdminQueues MySupportQueues
    RefreshHomepage Dashboards SavedSearches
    ClockWidget
    WeatherWidget
    ArticlesWidget
    AssetsWidget
    UserProfileWidget
    FeedWidget
)]);
```

### Ticket-Seiten-Widgets — Page Layout

Die folgenden Widgets stehen im Admin unter **Admin → Global → Page Layouts** zur Verfügung und können per Drag-and-Drop zu Ticket-Spalten hinzugefügt werden:

- `DisplaySLA` — SLA-Fristen-Widget
- `LifecycleWidget` — Lifecycle-Diagramm
- `LinkedArticles` — Verknüpfte Artikel

---

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

---

## Integrierte Erweiterungen

Ab v0.09 sind folgende vormals eigenständige Extensions vollständig in Redesign aufgegangen und müssen **nicht mehr** separat installiert oder in `RT_SiteConfig.pm` eingetragen werden:

| Extension | Integriert seit | Was sie bringt |
|---|---|---|
| RT-Extension-AdminDashboard | v0.07 | Admin-Seiten-Dashboard, Systemstatistiken, Login-Banner |
| RT-Extension-SyntaxHighlight | v0.09 | highlight.js für CKEditor-Code-Blöcke |
| RT-Extension-DisplaySLA | v0.09 | SLA-Fristen-Widget auf Ticket-Seiten |
| RT-Extension-LifecycleWidget | v0.09 | Lifecycle-SVG-Diagramm auf Ticket-Seiten |
| RT-Extension-LinkedArticles | v0.09 | Verknüpfte-Artikel-Widget auf Ticket-Seiten |
| RT-Extension-ClockWidget | v0.09 | Flip-Clock-Dashboard-Portlet |
| RT-Extension-WeatherWidget | v0.09 | Live-Wetter-Dashboard-Portlet |
| RT-Extension-FeedWidget | v0.09 | RSS/ATOM-Feed-Reader-Dashboard-Portlet |
| RT-Extension-UserProfileWidget | v0.09 | Nutzerprofil-Dashboard-Portlet |
| RT-Extension-ArticlesWidget | v0.09 | Neueste-Artikel-Dashboard-Portlet |
| RT-Extension-AssetsWidget | v0.09 | Aktualisierte-Assets-Dashboard-Portlet |

### Migration von eigenständigen Installationen

Falls eine oder mehrere dieser Extensions separat installiert sind:

1. Diese Extension installieren (`perl Makefile.PL && make && sudo make install`)
2. `Plugin('RT::Extension::XXX');` für jede der oben genannten Extensions aus `RT_SiteConfig.pm` entfernen
3. Für `RT-Extension-AdminDashboard`: Cron-Eintrag von `rt-admin-dashboard-refresh` auf `rt-redesign-stats-refresh` umstellen (Attributname `AdminDashboardStats` und Verhalten bleiben identisch)
4. Für `RT-Extension-FeedWidget`: CSRF-Whitelist hinzufügen (siehe [Konfiguration](#konfiguration))
5. Mason-Cache leeren und Apache neu starten

---

## Anforderungen

- Request Tracker 5.0 oder höher
- RT 7.0 nicht unterstützt

## Autor / Lizenz

Torsten Brumm — GNU General Public License v2
