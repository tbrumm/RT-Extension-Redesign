// RT::Extension::Redesign -- preferences feed editor (add/remove RSS/ATOM feed
// rows, keep the count badge current). Registered via
// RT->AddJavaScript('redesign/redesign-prefs.js') and initialised per card
// inside htmx.onLoad with a one-shot guard -- so it works both on the AboutMe
// page and after the Save button hx-swaps a fresh #fw-prefs-card back in.
// Localised labels for JS-built rows arrive in data-* attributes on the card.

(function () {
    'use strict';

    function each(root, selector, fn) {
        (root || document).querySelectorAll(selector).forEach(fn);
        if (root && root.nodeType === 1 && root.matches && root.matches(selector)) fn(root);
    }

    function initFeedsEditor(card) {
        if (card.dataset.feInit) return;
        card.dataset.feInit = '1';

        var list    = card.querySelector('#fw-feeds-list');
        var addBtn  = card.querySelector('#fw-add-row');
        var cntEl   = card.querySelector('#fw-feed-count');
        var labelPh = card.dataset.fwLabelPh || '';
        var removeT = card.dataset.fwRemove  || '';

        function updateCount() {
            if (cntEl && list) cntEl.textContent = list.querySelectorAll('.fw-feed-row').length;
        }

        function escAttr(s) {
            return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;')
                            .replace(/</g, '&lt;').replace(/>/g, '&gt;');
        }

        function addRow() {
            var idx = Date.now();
            var row = document.createElement('div');
            row.className = 'fw-feed-row row g-2 align-items-center mb-2';
            row.id = 'fw-row-' + idx;
            row.innerHTML =
                '<div class="col-md-5">' +
                    '<input type="url" name="fw_url" class="form-control form-control-sm"' +
                           ' placeholder="https://example.com/feed.rss" required>' +
                '</div>' +
                '<div class="col-md-4">' +
                    '<input type="text" name="fw_title" class="form-control form-control-sm"' +
                           ' placeholder="' + escAttr(labelPh) + '">' +
                '</div>' +
                '<div class="col-md-2">' +
                    '<input type="number" name="fw_max_items" class="form-control form-control-sm"' +
                           ' min="1" max="50" value="10">' +
                '</div>' +
                '<div class="col-md-1 text-end">' +
                    '<button type="button" class="btn btn-sm btn-outline-danger fw-remove-row"' +
                            ' title="' + escAttr(removeT) + '"><i class="bi bi-x-lg"></i></button>' +
                '</div>';
            list.appendChild(row);
            row.querySelector('input[type="url"]').focus();
            updateCount();
        }

        if (addBtn) addBtn.addEventListener('click', addRow);

        if (list) list.addEventListener('click', function (e) {
            var btn = e.target.closest('.fw-remove-row');
            if (!btn) return;
            var row = btn.closest('.fw-feed-row');
            if (row) { row.remove(); updateCount(); }
        });
    }

    function onLoad(root) {
        each(root, '#fw-prefs-card', initFeedsEditor);
    }

    if (typeof htmx !== 'undefined') {
        htmx.onLoad(onLoad);
    } else {
        document.addEventListener('DOMContentLoaded', function () { onLoad(document); });
    }
}());
