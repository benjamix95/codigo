(function() {
    'use strict';

    if (window.__codigoBridgeInstalled) return;
    window.__codigoBridgeInstalled = true;

    var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.browserbridge;
    if (!bridge) return;

    function post(type, payload) {
        try { bridge.postMessage({ type: type, payload: payload }); } catch(e) {}
    }

    // --- Console capture ---
    var levels = ['log', 'info', 'warn', 'error', 'debug'];
    levels.forEach(function(level) {
        var original = console[level];
        console[level] = function() {
            var args = Array.prototype.slice.call(arguments);
            var message = args.map(function(a) {
                if (a === null) return 'null';
                if (a === undefined) return 'undefined';
                if (typeof a === 'object') {
                    try { return JSON.stringify(a, null, 2); } catch(e) { return String(a); }
                }
                return String(a);
            }).join(' ');

            post('console', {
                level: level,
                message: message,
                timestamp: Date.now()
            });

            if (original) original.apply(console, arguments);
        };
    });

    // --- Uncaught error capture ---
    window.addEventListener('error', function(event) {
        post('jsError', {
            message: event.message || String(event.error),
            source: event.filename || null,
            line: event.lineno || null,
            col: event.colno || null,
            stack: event.error && event.error.stack ? event.error.stack : null,
            timestamp: Date.now()
        });
    });

    // --- Unhandled promise rejection capture ---
    window.addEventListener('unhandledrejection', function(event) {
        var reason = event.reason;
        var message = 'Unhandled Promise Rejection: ';
        if (reason instanceof Error) {
            message += reason.message;
        } else if (typeof reason === 'string') {
            message += reason;
        } else {
            try { message += JSON.stringify(reason); } catch(e) { message += String(reason); }
        }

        post('jsError', {
            message: message,
            source: null,
            line: null,
            col: null,
            stack: reason instanceof Error ? reason.stack : null,
            timestamp: Date.now()
        });
    });

    // --- Network request capture via PerformanceObserver ---
    if (typeof PerformanceObserver !== 'undefined') {
        try {
            var observer = new PerformanceObserver(function(list) {
                var entries = list.getEntries();
                entries.forEach(function(entry) {
                    if (entry.entryType !== 'resource') return;
                    post('network', {
                        url: entry.name,
                        initiatorType: entry.initiatorType || 'other',
                        duration: Math.round(entry.duration),
                        transferSize: entry.transferSize || 0,
                        timestamp: Date.now()
                    });
                });
            });
            observer.observe({ type: 'resource', buffered: false });
        } catch(e) {}
    }

    // --- XHR status capture ---
    var OrigXHR = XMLHttpRequest;
    var origOpen = OrigXHR.prototype.open;
    var origSend = OrigXHR.prototype.send;

    OrigXHR.prototype.open = function(method, url) {
        this.__codigo_method = method;
        this.__codigo_url = url;
        return origOpen.apply(this, arguments);
    };

    OrigXHR.prototype.send = function() {
        var xhr = this;
        var startTime = Date.now();
        xhr.addEventListener('loadend', function() {
            post('networkXHR', {
                url: xhr.__codigo_url || '',
                method: xhr.__codigo_method || 'GET',
                status: xhr.status,
                duration: Date.now() - startTime,
                timestamp: Date.now()
            });
        });
        return origSend.apply(this, arguments);
    };

    // --- Fetch capture ---
    var origFetch = window.fetch;
    if (origFetch) {
        window.fetch = function() {
            var args = arguments;
            var url = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url ? args[0].url : '');
            var method = (args[1] && args[1].method) ? args[1].method : 'GET';
            var startTime = Date.now();

            return origFetch.apply(this, arguments).then(function(response) {
                post('networkFetch', {
                    url: url,
                    method: method,
                    status: response.status,
                    duration: Date.now() - startTime,
                    timestamp: Date.now()
                });
                return response;
            }).catch(function(err) {
                post('networkFetch', {
                    url: url,
                    method: method,
                    status: 0,
                    duration: Date.now() - startTime,
                    error: err.message || String(err),
                    timestamp: Date.now()
                });
                throw err;
            });
        };
    }

    // --- Page lifecycle ---
    post('pageReady', { url: location.href, title: document.title, timestamp: Date.now() });

})();
