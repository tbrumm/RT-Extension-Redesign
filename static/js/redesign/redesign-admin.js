// RT::Extension::Redesign -- admin-page behaviour (Login Banner editor: live
// preview from the CKEditor instances, Info/Warning type toggle, preview
// Light/Dark toggle, floating "unsaved changes" save bar). Registered via
// RT->AddJavaScript('redesign/redesign-admin.js') and initialised inside
// htmx.onLoad with a one-shot guard. No inline <script>, no Perl interpolation
// (all state is read from the form/CKEditor at runtime).

(function () {
    'use strict';

    function each(root, selector, fn) {
        (root || document).querySelectorAll(selector).forEach(fn);
        if (root && root.nodeType === 1 && root.matches && root.matches(selector)) fn(root);
    }

    function initLoginBanner(box) {
        if (box.dataset.lbInit) return;
        box.dataset.lbInit = '1';

        var hl   = document.getElementById('preview-headline');
        var de   = document.getElementById('preview-content-de');
        var en   = document.getElementById('preview-content-en');
        var icon = document.getElementById('preview-icon');

        // Mirror RT::Extension::Redesign::strip_outer_paragraph for the headline.
        function stripP(html) {
            var m = /^\s*<p\b[^>]*>([\s\S]*)<\/p>\s*$/.exec(html || '');
            if (m && !/<\/?p\b/i.test(m[1])) return m[1];
            return html || '';
        }
        function data(name) {
            var inst = window.RT && RT.CKEditor && RT.CKEditor.instances && RT.CKEditor.instances[name];
            if (inst) return inst.getData();
            var ta = document.getElementById(name);
            return ta ? ta.value : '';
        }
        function update() {
            hl.innerHTML = stripP(data('BannerHeadline'));
            de.innerHTML = data('BannerContentDE');
            en.innerHTML = data('BannerContentEN');
        }
        function applyType() {
            var warn = document.getElementById('BannerTypeWarning');
            var isWarn = !!(warn && warn.checked);
            box.classList.toggle('rd-login-banner--warning', isWarn);
            if (icon) icon.innerHTML = isWarn ? '\u26A0' : '\u2713';
        }
        function applyPreviewTheme() {
            var dark = document.getElementById('PreviewThemeDark');
            var wrap = document.getElementById('rd-preview-theme');
            if (wrap) wrap.setAttribute('data-bs-theme', (dark && dark.checked) ? 'dark' : 'light');
        }
        var bar = document.getElementById('rd-banner-float-bar');
        function markChanged() { if (bar) bar.classList.remove('d-none'); }

        // CKEditor initialises asynchronously; wait for the instances, then bind.
        var tries = 0;
        var iv = setInterval(function () {
            tries++;
            var inst = window.RT && RT.CKEditor && RT.CKEditor.instances;
            var ready = inst && inst.BannerHeadline && inst.BannerContentDE && inst.BannerContentEN;
            if (ready || tries > 50) {
                clearInterval(iv);
                ['BannerHeadline', 'BannerContentDE', 'BannerContentEN'].forEach(function (n) {
                    var ed = inst && inst[n];
                    if (ed) ed.model.document.on('change:data', function () { update(); markChanged(); });
                });
                update();
                // Wire form-level change detection only after the initial state has
                // settled, so editor init / setData doesn't trip the save bar.
                var form = box.closest('form');
                if (form) form.addEventListener('change', function (e) {
                    // The preview Light/Dark toggle is a view-only control, not saved.
                    if (e.target && e.target.name === 'PreviewTheme') return;
                    markChanged();
                });
            }
        }, 150);

        ['BannerTypeInfo', 'BannerTypeWarning'].forEach(function (id) {
            var el = document.getElementById(id);
            if (el) el.addEventListener('change', applyType);
        });
        applyType();

        ['PreviewThemeLight', 'PreviewThemeDark'].forEach(function (id) {
            var el = document.getElementById(id);
            if (el) el.addEventListener('change', applyPreviewTheme);
        });
        applyPreviewTheme();
    }

    function onLoad(root) {
        each(root, '#rd-banner-preview', initLoginBanner);
    }

    if (typeof htmx !== 'undefined') {
        htmx.onLoad(onLoad);
    } else {
        document.addEventListener('DOMContentLoaded', function () { onLoad(document); });
    }
}());
