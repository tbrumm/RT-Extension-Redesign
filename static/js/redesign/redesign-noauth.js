// RT::Extension::Redesign -- NoAuth page behaviour (login promo fallback, login
// form hash-forwarding, logout countdown). Registered via
// RT->AddJavaScript('redesign/redesign-noauth.js'); the file is emitted into the
// NoAuth page head through /Elements/Header just like on authed pages. NoAuth
// pages are not hx-boosted, so the htmx.onLoad path simply falls back to
// DOMContentLoaded. Each initialiser guards itself and no-ops when its element
// is absent. No inline <script>, no Perl interpolation.

(function () {
    'use strict';

    function each(root, selector, fn) {
        (root || document).querySelectorAll(selector).forEach(fn);
        if (root && root.nodeType === 1 && root.matches && root.matches(selector)) fn(root);
    }

    // Login page: if the maintenance-banner output is empty, hide it and reveal
    // the "Why Request Tracker?" promo grid instead.
    function initPromoFallback(bf) {
        if (bf.dataset.pfInit) return;
        bf.dataset.pfInit = '1';
        var promo = document.getElementById('rd-promo-output');
        if (bf.innerHTML.trim() === '') {
            bf.style.display = 'none';
            if (promo) promo.style.display = '';
        }
    }

    // Login page: carry a URL fragment through the login POST so a deep link
    // survives authentication.
    function initLoginHash(form) {
        if (form.dataset.hashInit) return;
        form.dataset.hashInit = '1';
        if (window.location.hash) {
            form.setAttribute('action',
                form.getAttribute('action') + '#' + window.location.hash.replace(/^#/, ''));
        }
    }

    // Logout page: count the #rd-countdown number down to zero.
    function initLogoutCountdown(el) {
        if (el.dataset.cdInit) return;
        el.dataset.cdInit = '1';
        var count = parseInt(el.textContent, 10);
        if (!count) return;
        var timer = setInterval(function () {
            count--;
            el.textContent = count;
            if (count <= 0) clearInterval(timer);
        }, 1000);
    }

    function onLoad(root) {
        each(root, '#rd-bf-output',    initPromoFallback);
        each(root, 'form[name=login]', initLoginHash);
        each(root, '#rd-countdown',    initLogoutCountdown);
    }

    if (typeof htmx !== 'undefined') {
        htmx.onLoad(onLoad);
    } else {
        document.addEventListener('DOMContentLoaded', function () { onLoad(document); });
    }
}());
