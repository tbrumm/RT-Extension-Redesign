// RT::Extension::Redesign — global front-end behaviour, loaded on every page via
// RT->AddJavaScript('redesign/redesign-global.js'). Initialise inside htmx.onLoad
// (fires on first load AND after every hx-boost body swap) so nothing relies on
// DOMContentLoaded, which does not re-run after a boosted navigation.

(function () {
    'use strict';

    // ---- highlight.js code blocks in ticket message bodies -------------------
    var CODE_SEL = '.message-stanza pre code[class*="language-"]';

    function highlightAll(root) {
        if (typeof hljs === 'undefined') return;
        (root || document).querySelectorAll(CODE_SEL).forEach(function (el) {
            if (!el.classList.contains('hljs')) hljs.highlightElement(el);
        });
    }

    // ---- highlight.js light/dark theme follows RT's data-bs-theme ------------
    function syncTheme() {
        var dark = document.documentElement.getAttribute('data-bs-theme') === 'dark';
        var l = document.getElementById('hljs-theme-light');
        var d = document.getElementById('hljs-theme-dark');
        if (l) l.disabled = dark;
        if (d) d.disabled = !dark;
    }

    // Watch the theme toggle once for the life of the document. htmx.onLoad runs
    // on every swap, so guard the observer install with a flag.
    function installThemeObserver() {
        if (document.documentElement.dataset.redesignHljsThemeObserver) return;
        document.documentElement.dataset.redesignHljsThemeObserver = '1';
        if (typeof MutationObserver === 'undefined') return;
        new MutationObserver(syncTheme).observe(
            document.documentElement,
            { attributes: true, attributeFilter: ['data-bs-theme'] }
        );
    }

    function init(root) {
        installThemeObserver();
        syncTheme();
        highlightAll(root);
    }

    if (typeof htmx !== 'undefined') {
        htmx.onLoad(init);
    } else {
        document.addEventListener('DOMContentLoaded', function () { init(document); });
    }
}());
