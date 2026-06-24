// RT::Extension::Redesign -- ticket & article display behaviour (lifecycle graph,
// due-date / SLA badge colouring, recently-viewed article recorder). Registered
// via RT->AddJavaScript('redesign/redesign-ticket.js'). Everything initialises
// per element inside htmx.onLoad with a one-shot guard, so it survives hx-boost
// body swaps. Per-request data travels in data-* attributes, never inline JS.

(function () {
    'use strict';

    function each(root, selector, fn) {
        (root || document).querySelectorAll(selector).forEach(fn);
        if (root && root.nodeType === 1 && root.matches && root.matches(selector)) fn(root);
    }

    // ===== Lifecycle transition graph =========================================
    function initLifecycle(wrap) {
        if (wrap.dataset.lwInit) return;
        wrap.dataset.lwInit = '1';

        var NS  = 'http://www.w3.org/2000/svg';
        var WID = wrap.id;

        var data;
        try { data = JSON.parse(wrap.getAttribute('data-lc') || '{}'); } catch (e) { return; }
        var LW_LABELS = data.labels || { initial: 'Initial', active: 'Active', inactive: 'Inactive', complex: '%1' };

        var svg  = document.getElementById(WID + '-svg');
        var info = document.getElementById(WID + '-info');
        if (!svg) return;

        function el(tag, attrs) {
            var e = document.createElementNS(NS, tag);
            if (attrs) Object.keys(attrs).forEach(function (k) { e.setAttribute(k, attrs[k]); });
            return e;
        }
        function trunc(s, max) { return s.length > max ? s.slice(0, max - 1) + '\u2026' : s; }

        var lastW = 0;
        function update() {
            var w = wrap.getBoundingClientRect().width || wrap.offsetWidth;
            if (!w || Math.abs(w - lastW) < 4) return;
            lastW = w;
            render(w);
        }

        if (typeof ResizeObserver !== 'undefined') {
            new ResizeObserver(update).observe(wrap);
        } else {
            window.addEventListener('resize', update);
        }
        setTimeout(update, 0);
        setTimeout(update, 80);
        setTimeout(update, 400);

        function render(cW) {
            while (svg.firstChild) svg.removeChild(svg.firstChild);
            if (info) info.style.display = 'none';

            var ini = data.initial || [], act = data.active || [], ina = data.inactive || [];
            var cur = data.current || '', trans = data.transitions || {};
            var total = ini.length + act.length + ina.length;

            var NW, NH, RG, CG, maxLbl, fz;
            if      (cW >= 500) { NW = 120; NH = 30; RG = 8; CG = 72; maxLbl = 14; fz = 11; }
            else if (cW >= 370) { NW = 96;  NH = 28; RG = 7; CG = 50; maxLbl = 11; fz = 11; }
            else if (cW >= 260) { NW = 76;  NH = 26; RG = 6; CG = 30; maxLbl = 9;  fz = 10; }
            else                { NW = Math.max(55, Math.floor((cW - 24) / 2));
                                  NH = 24; RG = 5; CG = 0; maxLbl = Math.floor(NW / 8); fz = 9; }

            var NARROW = (cW < 260);
            var PAD = 16, TPAD = NARROW ? 20 : 38;

            var nodes = {}, typeOf = {};
            ini.forEach(function (s) { typeOf[s] = 'initial'; });
            act.forEach(function (s) { typeOf[s] = 'active'; });
            ina.forEach(function (s) { typeOf[s] = 'inactive'; });

            if (NARROW) {
                var all = ini.concat(act, ina);
                var stride = NW + 4;
                all.forEach(function (s, i) {
                    nodes[s] = { x: PAD + (i % 2) * stride, y: TPAD + Math.floor(i / 2) * (NH + RG), type: typeOf[s] };
                });
            } else {
                var ACT_COLS = act.length > 16 ? 3 : act.length > 8 ? 2 : 1;
                var ACT_W    = NW + 16;
                var xIni = PAD, xAct = PAD + NW + CG, xIna = xAct + ACT_COLS * ACT_W - 16 + CG;
                ini.forEach(function (s, i) { nodes[s] = { x: xIni, y: TPAD + i * (NH + RG), type: 'initial' }; });
                act.forEach(function (s, i) { nodes[s] = { x: xAct + (i % ACT_COLS) * ACT_W, y: TPAD + Math.floor(i / ACT_COLS) * (NH + RG), type: 'active' }; });
                ina.forEach(function (s, i) { nodes[s] = { x: xIna, y: TPAD + i * (NH + RG), type: 'inactive' }; });
            }

            var allN = Object.keys(nodes).map(function (k) { return nodes[k]; }), svgW = PAD, svgH = PAD;
            allN.forEach(function (n) {
                if (n.x + NW + PAD > svgW) svgW = n.x + NW + PAD;
                if (n.y + NH + PAD > svgH) svgH = n.y + NH + PAD;
            });
            svg.setAttribute('viewBox', '0 0 ' + svgW + ' ' + svgH);
            svg.setAttribute('width',  Math.min(svgW, cW));
            svg.setAttribute('height', svgH);

            var defs = el('defs');
            function mkMk(id, cls) {
                var m = el('marker', { id: WID + '-' + id, markerWidth: '8', markerHeight: '6', refX: '7', refY: '3', orient: 'auto' });
                m.appendChild(el('polygon', { points: '0 0,8 3,0 6', class: cls })); return m;
            }
            defs.appendChild(mkMk('mk', 'lw-mkarr')); defs.appendChild(mkMk('mk-cur', 'lw-mkarr-cur'));
            svg.appendChild(defs);

            var lsz = Math.max(8, fz - 1);
            if (!NARROW) {
                var ACT_COLS2 = act.length > 16 ? 3 : act.length > 8 ? 2 : 1, ACT_W2 = NW + 16;
                if (ini.length) { var xi = nodes[ini[0]].x; svg.appendChild(mkLbl(xi + NW / 2, TPAD - 8, LW_LABELS.initial, lsz)); }
                if (act.length) { var xa = nodes[act[0]].x; svg.appendChild(mkLbl(xa + (ACT_COLS2 * ACT_W2 - 16) / 2, TPAD - 8, LW_LABELS.active, lsz)); }
                if (ina.length) { var xn = nodes[ina[0]].x; svg.appendChild(mkLbl(xn + NW / 2, TPAD - 8, LW_LABELS.inactive, lsz)); }
            } else {
                var seen = {};
                ['initial', 'active', 'inactive'].forEach(function (t) {
                    var first = Object.keys(nodes).filter(function (s) { return nodes[s].type === t && !seen[s]; })[0];
                    if (!first) return;
                    var n = nodes[first];
                    svg.appendChild(mkLbl(PAD, n.y - 3, LW_LABELS[t] || (t.charAt(0).toUpperCase() + t.slice(1)), lsz - 1, 'lw-sec-lbl'));
                    seen[first] = 1;
                });
            }
            function mkLbl(x, y, txt, sz, cls) {
                var t = el('text', { x: x, y: y, 'text-anchor': 'middle', 'font-size': sz, class: cls || 'lw-col-label' });
                t.textContent = txt; return t;
            }

            if (!NARROW) {
                var SIMPLE = (total <= 20), transShow = {};
                if (SIMPLE) { transShow = trans; }
                else {
                    if (trans[cur]) transShow[cur] = trans[cur];
                    Object.keys(trans).forEach(function (f) { if ((trans[f] || []).indexOf(cur) !== -1) transShow[f] = transShow[f] || trans[f]; });
                    if (info) { info.style.display = ''; info.textContent = LW_LABELS.complex.replace('%1', total); }
                }
                var bc = 0, al = el('g'); svg.appendChild(al);
                Object.keys(transShow).forEach(function (from) {
                    if (!nodes[from]) return;
                    (transShow[from] || []).forEach(function (to) {
                        if (!nodes[to] || from === to) return;
                        var ic = (from === cur || to === cur);
                        var ib = nodes[from].x >= nodes[to].x - 5 && Math.abs(nodes[from].x - nodes[to].x) >= 5;
                        var d = aPath(nodes[from], nodes[to], ib ? bc++ : 0, NW, NH);
                        al.appendChild(el('path', { d: d, fill: 'none',
                            class: ic ? 'lw-arr lw-arr-cur' : 'lw-arr',
                            'marker-end': 'url(#' + WID + (ic ? '-mk-cur' : '-mk') + ')' }));
                    });
                });
            }

            Object.keys(nodes).forEach(function (s) {
                var n = nodes[s], ic = (s === cur);
                var g = el('g', { class: 'lw-node lw-' + n.type + (ic ? ' lw-current' : '') });
                var tt = document.createElementNS(NS, 'title'); tt.textContent = s + (ic ? ' (current)' : ''); g.appendChild(tt);
                g.appendChild(el('rect', { x: n.x, y: n.y, width: NW, height: NH, rx: '4', ry: '4', class: 'lw-rect' }));
                var t = el('text', { x: n.x + NW / 2, y: n.y + NH / 2, 'text-anchor': 'middle', 'dominant-baseline': 'central', 'font-size': fz, class: 'lw-lbl' });
                t.textContent = trunc(s, maxLbl); g.appendChild(t);
                svg.appendChild(g);
            });
        }

        function aPath(src, dst, bo, NW, NH) {
            if (Math.abs(src.x - dst.x) < 5) {
                var sx = src.x + NW, sy = src.y + NH / 2, dx = dst.x + NW, dy = dst.y + NH / 2, mx = sx + 30 + Math.abs(sy - dy) * 0.25;
                return 'M' + sx + ',' + sy + ' C' + mx + ',' + sy + ' ' + mx + ',' + dy + ' ' + dx + ',' + dy;
            }
            if (src.x < dst.x - 5) {
                var sx2 = src.x + NW, sy2 = src.y + NH / 2, dx2 = dst.x, dy2 = dst.y + NH / 2, mx2 = (sx2 + dx2) / 2;
                return 'M' + sx2 + ',' + sy2 + ' C' + mx2 + ',' + sy2 + ' ' + mx2 + ',' + dy2 + ' ' + dx2 + ',' + dy2;
            }
            var sx3 = src.x, sy3 = src.y + NH / 2, dx3 = dst.x + NW, dy3 = dst.y + NH / 2, ay = 6 + bo * 10;
            return 'M' + sx3 + ',' + sy3 + ' C' + sx3 + ',' + ay + ' ' + dx3 + ',' + ay + ' ' + dx3 + ',' + dy3;
        }
    }

    // ===== Due-date badge colouring ===========================================
    // The Perl callback computes the class and ships it on a hidden marker; apply
    // it to the core due-date value, then drop the marker.
    function initDueFlag(flag) {
        var el = document.querySelector('.date.due .current-value');
        if (el) { el.classList.remove('overdue'); el.classList.add(flag.dataset.dueClass); }
        flag.remove();
    }

    // ===== SLA badge colouring ================================================
    function initSlaFlag(flag) {
        var el = document.querySelector('.sla .current_value');
        if (el) { el.classList.add(flag.dataset.slaClass); }
        flag.remove();
    }

    // ===== Recently-viewed article recorder (localStorage writer) =============
    function initArticleRecorder(rec) {
        if (rec.dataset.raInit) return;
        rec.dataset.raInit = '1';

        var entry = {
            id:   parseInt(rec.dataset.raId, 10),
            name: rec.dataset.raName,
            cls:  rec.dataset.raClass,
            url:  rec.dataset.raUrl,
            ts:   Date.now()
        };
        var list = [];
        try { list = JSON.parse(localStorage.getItem('rt_recent_articles') || '[]'); } catch (e) {}
        list = list.filter(function (a) { return a.id !== entry.id; });
        list.unshift(entry);
        if (list.length > 5) list = list.slice(0, 5);
        try { localStorage.setItem('rt_recent_articles', JSON.stringify(list)); } catch (e) {}
    }

    function onLoad(root) {
        each(root, '[data-lc]',             initLifecycle);
        each(root, '.rt-due-flag',          initDueFlag);
        each(root, '.rt-sla-flag',          initSlaFlag);
        each(root, '.rt-article-recorder',  initArticleRecorder);
    }

    if (typeof htmx !== 'undefined') {
        htmx.onLoad(onLoad);
    } else {
        document.addEventListener('DOMContentLoaded', function () { onLoad(document); });
    }
}());
