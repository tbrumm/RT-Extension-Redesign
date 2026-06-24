// RT::Extension::Redesign -- homepage/dashboard widgets (Clock, Weather, Feed
// Reader, Recently-viewed articles). Registered via
// RT->AddJavaScript('redesign/redesign-widgets.js'). Each widget initialises
// per element inside htmx.onLoad with a one-shot guard, so it runs on first load
// AND after an hx-boost body swap without ever double-binding.
//
// Per-request data (localised labels, user profile, feed config) is passed from
// Mason as JSON in data-* attributes on the widget root, never interpolated into
// an inline <script>.

(function () {
    'use strict';

    // Run fn for each selector match under root, plus root itself if it matches.
    function each(root, selector, fn) {
        (root || document).querySelectorAll(selector).forEach(fn);
        if (root && root.nodeType === 1 && root.matches && root.matches(selector)) fn(root);
    }

    // ===== Flip clock =========================================================
    function initClock(wrap) {
        if (wrap.dataset.fcInit) return;
        wrap.dataset.fcInit = '1';

        var cfg;
        try { cfg = JSON.parse(wrap.dataset.fcConfig); } catch (e) { return; }
        var DAYS = cfg.days, MONTHS = cfg.months;
        var ID = wrap.id;

        function byId(s) { return document.getElementById(ID + '-' + s); }

        function Digit(key) {
            var d = byId(key);
            if (!d) return null;
            return {
                el: d,
                hi: d.querySelector('.fc-hi .fc-n'),
                lo: d.querySelector('.fc-lo .fc-n'),
                fl: d.querySelector('.fc-fl .fc-n'),
                v:  null
            };
        }

        var D = {
            h0: Digit('h0'), h1: Digit('h1'),
            m0: Digit('m0'), m1: Digit('m1')
        };

        function set(d, val) {
            if (!d) return;
            var v = String(val);
            if (d.v === null) {
                d.hi.textContent = d.lo.textContent = d.fl.textContent = v;
                d.v = v;
                return;
            }
            if (d.v === v) return;

            d.fl.textContent = d.v;
            d.hi.textContent = v;
            d.lo.textContent = v;

            d.el.classList.remove('flipping');
            void d.el.offsetWidth;
            d.el.classList.add('flipping');

            d.v = v;
            setTimeout(function () {
                d.el.classList.remove('flipping');
                d.fl.textContent = v;
            }, 400);
        }

        function tick() {
            var n = new Date();
            var h = n.getHours(), m = n.getMinutes();
            set(D.h0, Math.floor(h / 10)); set(D.h1, h % 10);
            set(D.m0, Math.floor(m / 10)); set(D.m1, m % 10);
            var de = byId('date');
            if (de) {
                de.textContent =
                    DAYS[n.getDay()] + ', ' + n.getDate() + '. ' +
                    MONTHS[n.getMonth()] + ' ' + n.getFullYear();
            }
        }

        tick();
        var t = setInterval(function () {
            if (!document.body.contains(wrap)) { clearInterval(t); return; }
            tick();
        }, 1000);
    }

    // ===== Weather ============================================================
    function initWeather(wrap) {
        if (wrap.dataset.wwInit) return;
        wrap.dataset.wwInit = '1';

        var cfg;
        try { cfg = JSON.parse(wrap.dataset.wwConfig); } catch (e) { return; }
        var CITY = cfg.city, ZIP = cfg.zip, COUNTRY = cfg.country, DISP_LOC = cfg.loc;
        var UNIT = cfg.unit, LANG = cfg.lang, L = cfg.labels;
        var CACHE_KEY = 'ww_v1_' + (CITY + '|' + ZIP + '|' + COUNTRY).replace(/[^a-z0-9]/gi, '_');
        var CACHE_TTL = 30 * 60 * 1000;

        // Icons as \uXXXX escapes -- keep this file pure ASCII so RT's asset
        // squisher can never corrupt a multi-byte glyph.
        var IC = {
            0:  '\u2600\uFE0F',
            1:  '\uD83C\uDF24\uFE0F',
            2:  '\u26C5',
            3:  '\u2601\uFE0F',
            45: '\uD83C\uDF2B\uFE0F',
            48: '\uD83C\uDF2B\uFE0F',
            51: '\uD83C\uDF26\uFE0F',
            53: '\uD83C\uDF26\uFE0F',
            55: '\uD83C\uDF27\uFE0F',
            56: '\uD83C\uDF27\uFE0F',
            57: '\uD83C\uDF27\uFE0F',
            61: '\uD83C\uDF27\uFE0F',
            63: '\uD83C\uDF27\uFE0F',
            65: '\uD83C\uDF27\uFE0F',
            66: '\uD83C\uDF28\uFE0F',
            67: '\uD83C\uDF28\uFE0F',
            71: '\uD83C\uDF28\uFE0F',
            73: '\u2744\uFE0F',
            75: '\u2744\uFE0F',
            77: '\uD83C\uDF28\uFE0F',
            80: '\uD83C\uDF26\uFE0F',
            81: '\uD83C\uDF27\uFE0F',
            82: '\uD83C\uDF27\uFE0F',
            85: '\uD83C\uDF28\uFE0F',
            86: '\u2744\uFE0F',
            95: '\u26C8\uFE0F',
            96: '\u26C8\uFE0F',
            99: '\u26C8\uFE0F',
            night:   '\uD83C\uDF19',
            unknown: '\uD83C\uDF21\uFE0F',
            pin:     '\uD83D\uDCCD',
            wind:    '\uD83D\uDCA8',
            hum:     '\uD83D\uDCA7'
        };

        var sLoad   = wrap.querySelector('.ww-loading');
        var sErr    = wrap.querySelector('.ww-error');
        var sCont   = wrap.querySelector('.ww-content');
        var errMsg  = wrap.querySelector('.ww-err-msg');
        var iconEl  = wrap.querySelector('.ww-icon');
        var tempEl  = wrap.querySelector('.ww-temp');
        var condEl  = wrap.querySelector('.ww-cond');
        var locEl   = wrap.querySelector('.ww-loc');
        var feelsEl = wrap.querySelector('.ww-feels');
        var windEl  = wrap.querySelector('.ww-wind');
        var humEl   = wrap.querySelector('.ww-hum');
        var updEl   = wrap.querySelector('.ww-updated');

        var _loadTimer = null;

        function showState(el) {
            if (_loadTimer) { clearTimeout(_loadTimer); _loadTimer = null; }
            [sLoad, sErr, sCont].forEach(function (e) { e.hidden = true; });
            el.hidden = false;
        }

        function showLoading() {
            [sLoad, sErr, sCont].forEach(function (e) { e.hidden = true; });
            sLoad.hidden = false;
            _loadTimer = setTimeout(function () { showError(L.timeout); }, 12000);
        }

        function showError(msg) {
            errMsg.textContent = msg;
            showState(sErr);
        }

        function render(weather) {
            var cur   = weather.current;
            var code  = cur.weather_code;
            var isDay = cur.is_day !== 0;
            var c10   = Math.floor(code / 10) * 10;
            var icon  = IC[code]  || IC[c10]  || IC.unknown;
            var label = L.wmo_labels[code] || L.wmo_labels[c10] || L.wmo_labels.unknown;

            if (!isDay && code === 0) {
                icon  = IC.night;
                label = L.wmo_labels.night;
            }

            var deg    = '\u00B0' + (UNIT === 'fahrenheit' ? 'F' : 'C');
            var temp   = Math.round(cur.temperature_2m);
            var feels  = Math.round(cur.apparent_temperature);
            var wind   = Math.round(cur.wind_speed_10m);
            var hum    = cur.relative_humidity_2m;
            var now    = new Date();
            var timeStr = now.toLocaleTimeString(LANG, { hour: '2-digit', minute: '2-digit' });

            iconEl.textContent  = icon;
            tempEl.textContent  = temp + deg;
            condEl.textContent  = label;
            locEl.textContent   = IC.pin + ' ' + DISP_LOC;
            feelsEl.textContent = L.feels_like + ' ' + feels + deg;
            windEl.textContent  = IC.wind + ' ' + wind + ' km/h';
            humEl.textContent   = IC.hum + ' ' + hum + ' %';
            updEl.textContent   = L.updated + ' ' + timeStr;

            showState(sCont);

            try {
                sessionStorage.setItem(CACHE_KEY, JSON.stringify({ ts: Date.now(), weather: weather }));
            } catch (e) {}
        }

        function fetchWeather(lat, lon) {
            var url = 'https://api.open-meteo.com/v1/forecast'
                + '?latitude='  + lat
                + '&longitude=' + lon
                + '&current=temperature_2m,apparent_temperature,weather_code,'
                + 'wind_speed_10m,relative_humidity_2m,is_day'
                + '&wind_speed_unit=kmh'
                + '&temperature_unit=' + UNIT
                + '&timezone=auto';

            fetch(url)
                .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
                .then(function (data) { render(data); })
                .catch(function () { showError(L.wx_fail); });
        }

        function geocodeViaNominatim() {
            var params = ['format=json', 'limit=1', 'addressdetails=0'];
            if (ZIP)     params.push('postalcode=' + encodeURIComponent(ZIP));
            if (CITY)    params.push('city='       + encodeURIComponent(CITY));
            if (COUNTRY) params.push('country='    + encodeURIComponent(COUNTRY));

            fetch('https://nominatim.openstreetmap.org/search?' + params.join('&'), {
                headers: { 'Accept-Language': LANG }
            })
                .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
                .then(function (data) {
                    if (!data || !data.length) { showError(L.loc_nf); return; }
                    fetchWeather(parseFloat(data[0].lat), parseFloat(data[0].lon));
                })
                .catch(function () { showError(L.geo_fail); });
        }

        function geocodeAndLoad() {
            if (!CITY) { geocodeViaNominatim(); return; }

            var url = 'https://geocoding-api.open-meteo.com/v1/search'
                + '?name='     + encodeURIComponent(CITY)
                + '&count=10'
                + '&language=' + encodeURIComponent(LANG)
                + '&format=json';

            fetch(url)
                .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
                .then(function (data) {
                    if (!data || !data.results || !data.results.length) { geocodeViaNominatim(); return; }
                    var result = data.results[0];
                    if (COUNTRY) {
                        var cLow = COUNTRY.toLowerCase();
                        var match = data.results.filter(function (r) {
                            return (r.country      && r.country.toLowerCase()      === cLow) ||
                                   (r.country_code && r.country_code.toLowerCase() === cLow);
                        })[0];
                        if (match) result = match;
                    }
                    fetchWeather(result.latitude, result.longitude);
                })
                .catch(function () { geocodeViaNominatim(); });
        }

        function init() {
            showLoading();
            try {
                var cached = JSON.parse(sessionStorage.getItem(CACHE_KEY));
                if (cached && (Date.now() - cached.ts) < CACHE_TTL) { render(cached.weather); return; }
            } catch (e) {}
            geocodeAndLoad();
        }

        wrap.querySelector('.ww-retry-btn').addEventListener('click', function () {
            try { sessionStorage.removeItem(CACHE_KEY); } catch (e) {}
            init();
        });
        wrap.querySelector('.ww-refresh-btn').addEventListener('click', function () {
            try { sessionStorage.removeItem(CACHE_KEY); } catch (e) {}
            init();
        });

        try { init(); } catch (e) { showError(L.int_err + ' ' + e.message); }
    }

    // ===== Feed reader ========================================================
    function initFeed(wrap) {
        if (wrap.dataset.fwInit) return;
        wrap.dataset.fwInit = '1';

        var FEEDS, FETCH, FW_NO_ITEMS;
        try {
            FEEDS = JSON.parse(wrap.dataset.fwFeeds);
            FETCH = wrap.dataset.fwFetch;
            FW_NO_ITEMS = wrap.dataset.fwNoItems;
        } catch (e) { return; }

        var ID     = wrap.id;
        var sLoad  = wrap.querySelector('.fw-loading');
        var sErr   = wrap.querySelector('.fw-error');
        var sCont  = wrap.querySelector('.fw-content');
        var tabBar = document.getElementById(ID + '-tabs');
        var panels = document.getElementById(ID + '-panels');

        function showState(el) {
            [sLoad, sErr, sCont].forEach(function (e) { e.hidden = true; });
            el.hidden = false;
        }

        function activateTab(idx) {
            tabBar.querySelectorAll('.fw-tab').forEach(function (t, i) { t.classList.toggle('active', i === idx); });
            panels.querySelectorAll('.fw-panel').forEach(function (p, i) { p.classList.toggle('active', i === idx); });
        }

        function buildTab(label, idx, hasError) {
            var btn = document.createElement('button');
            btn.className = 'fw-tab';
            btn.setAttribute('role', 'tab');
            btn.title = label;
            btn.textContent = label;
            if (hasError) {
                var dot = document.createElement('span');
                dot.className = 'fw-tab-err';
                btn.appendChild(dot);
            }
            btn.addEventListener('click', function () { activateTab(idx); });
            tabBar.appendChild(btn);
        }

        function buildPanel(feedData) {
            var panel = document.createElement('div');
            panel.className = 'fw-panel';

            if (feedData.error) {
                var errDiv = document.createElement('div');
                errDiv.className = 'fw-panel-error';
                errDiv.textContent = feedData.error;
                panel.appendChild(errDiv);
            } else {
                var ul = document.createElement('ul');
                ul.className = 'fw-items';
                var items = feedData.items || [];
                if (!items.length) {
                    var li = document.createElement('li');
                    li.className = 'fw-item';
                    li.style.textAlign = 'center';
                    li.style.color = 'var(--bs-secondary-color)';
                    li.style.fontSize = '0.8rem';
                    li.style.padding = '1rem';
                    li.textContent = FW_NO_ITEMS;
                    ul.appendChild(li);
                }
                items.forEach(function (item) {
                    var li = document.createElement('li');
                    li.className = 'fw-item';

                    var a = document.createElement('a');
                    a.className = 'fw-item-title';
                    a.href = item.link || '#';
                    a.target = '_blank';
                    a.rel = 'noopener noreferrer';
                    a.textContent = item.title || '(no title)';
                    li.appendChild(a);

                    if (item.pubdate) {
                        var meta = document.createElement('div');
                        meta.className = 'fw-item-meta';
                        meta.textContent = item.pubdate;
                        li.appendChild(meta);
                    }

                    if (item.summary) {
                        var sum = document.createElement('div');
                        sum.className = 'fw-item-summary';
                        sum.textContent = item.summary;
                        li.appendChild(sum);
                    }

                    ul.appendChild(li);
                });
                panel.appendChild(ul);
            }

            panels.appendChild(panel);
            return panel;
        }

        function load() {
            showState(sLoad);
            tabBar.innerHTML = '';
            panels.innerHTML = '';

            var pending = FEEDS.length;
            var results = new Array(FEEDS.length);

            function done(idx, data) {
                results[idx] = data;
                pending--;
                if (pending === 0) { render(results); }
            }

            FEEDS.forEach(function (feed, idx) {
                var url = FETCH + '?url=' + encodeURIComponent(feed.url)
                                + '&max=' + encodeURIComponent(feed.max_items || 10);
                fetch(url, { credentials: 'same-origin' })
                    .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
                    .then(function (data) { done(idx, data); })
                    .catch(function (e) { done(idx, { error: e.message, items: [] }); });
            });
        }

        function render(results) {
            if (!results.length) { showState(sErr); return; }

            results.forEach(function (data, idx) {
                var cfg   = FEEDS[idx];
                var label = data.feed_title || cfg.title || cfg.url;
                if (label.length > 20) label = label.substring(0, 18) + '\u2026';
                buildTab(label, idx, !!data.error);
                buildPanel(data);
            });

            activateTab(0);
            showState(sCont);
        }

        wrap.querySelector('.fw-retry-btn').addEventListener('click', load);
        wrap.querySelector('.fw-refresh-btn').addEventListener('click', load);

        load();
    }

    // ===== Recently viewed articles (localStorage reader) =====================
    function initRecentArticles(container) {
        if (container.dataset.raInit) return;
        container.dataset.raInit = '1';

        var list = [];
        try { list = JSON.parse(localStorage.getItem('rt_recent_articles') || '[]'); } catch (e) {}
        if (!list.length) return;

        function esc(s) {
            return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
                            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
        }

        var html = '';
        list.forEach(function (a) {
            html += '<div class="card mb-2 article-card">'
                  + '<div class="card-body py-2 px-3">'
                  + '<div class="d-flex justify-content-between align-items-start gap-2">'
                  + '<a href="' + esc(a.url) + '" class="fw-semibold text-body article-card-title">' + esc(a.name) + '</a>'
                  + '<span class="badge text-bg-secondary text-nowrap flex-shrink-0">' + esc(a.cls) + '</span>'
                  + '</div>'
                  + '</div></div>';
        });
        container.innerHTML = html;
    }

    function onLoad(root) {
        each(root, '.fc-wrap[data-fc-config]', initClock);
        each(root, '.ww-wrap[data-ww-config]', initWeather);
        each(root, '.fw-wrap[data-fw-feeds]',  initFeed);
        each(root, '#articles-recently-viewed', initRecentArticles);
    }

    if (typeof htmx !== 'undefined') {
        htmx.onLoad(onLoad);
    } else {
        document.addEventListener('DOMContentLoaded', function () { onLoad(document); });
    }
}());
