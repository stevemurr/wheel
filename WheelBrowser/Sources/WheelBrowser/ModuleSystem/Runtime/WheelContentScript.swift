import Foundation
import WebKit

/// Generates WKUserScripts with the `wheel.*` DOM API for content scripts.
/// Each module runs in its own isolated `WKContentWorld`.
enum WheelContentScript {

    /// Build a WKUserScript for a module's content script with wheel.* API injection.
    static func build(for manifest: ModuleManifest) -> WKUserScript? {
        guard let script = manifest.contentScript else { return nil }

        let wrappedScript = wrapForExecution(script: script, manifest: manifest)

        return WKUserScript(
            source: wrappedScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: contentWorld(for: manifest.id)
        )
    }

    /// Build a WKUserScript that injects CSS styles.
    static func buildCSSInjection(moduleId: UUID, styles: [String]) -> WKUserScript? {
        guard !styles.isEmpty else { return nil }

        let combinedCSS = styles.joined(separator: "\n")
        let escapedCSS = combinedCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let script = """
        (function() {
            const style = document.createElement('style');
            style.id = 'wheel-module-\(moduleId.uuidString)';
            style.textContent = '\(escapedCSS)';
            (document.head || document.documentElement).appendChild(style);
        })();
        """

        return WKUserScript(
            source: script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: contentWorld(for: moduleId)
        )
    }

    /// Wrap a content script with the wheel.* API based on granted permissions.
    static func wrapForExecution(script: String, manifest: ModuleManifest) -> String {
        var apiParts: [String] = []

        // Always provide the base wheel object
        apiParts.append("const wheel = {};")

        // page.read permission
        if manifest.permissions.contains(.pageRead) {
            apiParts.append(pageAPI)
        }

        // DOM query permission
        if manifest.permissions.contains(.domQuery) {
            apiParts.append(domQueryAPI)
        }

        // DOM modify permission
        if manifest.permissions.contains(.domModify) {
            apiParts.append(domModifyAPI)
        }

        // CSS injection permission
        if manifest.permissions.contains(.domCSSInject) {
            apiParts.append(domCSSAPI(moduleId: manifest.id))
        }

        // DOM observe permission
        if manifest.permissions.contains(.domObserve) {
            apiParts.append(domObserveAPI)
        }

        // Storage permission
        if manifest.permissions.contains(.storageLocal) {
            apiParts.append(storageAPI(moduleId: manifest.id))
        }

        // Messaging
        apiParts.append(messagingAPI(moduleId: manifest.id))

        // Result function (for skills)
        apiParts.append(resultAPI)

        let api = apiParts.joined(separator: "\n\n")

        return """
        (async function() {
            'use strict';
            try {
                \(api)

                \(script)
            } catch(e) {
                window.webkit?.messageHandlers?.wheelModuleError?.postMessage({
                    moduleId: '\(manifest.id.uuidString)',
                    error: e.message || String(e)
                });
            }
        })();
        """
    }

    /// Get the isolated content world for a module.
    static func contentWorld(for moduleId: UUID) -> WKContentWorld {
        WKContentWorld.world(name: "wheel-module-\(moduleId.uuidString)")
    }

    // MARK: - API Definitions

    private static let pageAPI = """
    wheel.page = {
        get url() { return window.location.href; },
        get title() { return document.title; },
        get domain() { return window.location.hostname; },
        onNavigate(callback) {
            // SPA navigation detection
            const observer = new MutationObserver(() => {
                callback({ url: window.location.href, title: document.title });
            });
            observer.observe(document.querySelector('title') || document.head, {
                childList: true, subtree: true, characterData: true
            });
            window.addEventListener('popstate', () => {
                callback({ url: window.location.href, title: document.title });
            });
        }
    };
    """

    private static let domQueryAPI = """
    wheel.dom = wheel.dom || {};
    wheel.dom.query = function(selector) {
        const el = document.querySelector(selector);
        if (!el) return null;
        return {
            text: el.textContent,
            html: el.innerHTML,
            attrs: Object.fromEntries(Array.from(el.attributes).map(a => [a.name, a.value]))
        };
    };
    wheel.dom.queryAll = function(selector) {
        return Array.from(document.querySelectorAll(selector)).map(el => ({
            text: el.textContent,
            html: el.innerHTML,
            attrs: Object.fromEntries(Array.from(el.attributes).map(a => [a.name, a.value]))
        }));
    };
    wheel.dom.getText = function(selector) {
        const el = document.querySelector(selector);
        return el ? el.textContent : null;
    };
    """

    private static let domModifyAPI = """
    wheel.dom = wheel.dom || {};
    wheel.dom.remove = function(selector) {
        document.querySelectorAll(selector).forEach(el => el.remove());
    };
    wheel.dom.setAttribute = function(selector, attr, value) {
        document.querySelectorAll(selector).forEach(el => el.setAttribute(attr, value));
    };
    wheel.dom.addClass = function(selector, className) {
        document.querySelectorAll(selector).forEach(el => el.classList.add(className));
    };
    """

    private static func domCSSAPI(moduleId: UUID) -> String {
        """
        wheel.dom = wheel.dom || {};
        wheel.dom.injectCSS = function(id, cssString) {
            let style = document.getElementById('wheel-css-' + id);
            if (!style) {
                style = document.createElement('style');
                style.id = 'wheel-css-' + id;
                (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = cssString;
        };
        wheel.dom.removeCSS = function(id) {
            const style = document.getElementById('wheel-css-' + id);
            if (style) style.remove();
        };
        """
    }

    private static let domObserveAPI = """
    wheel.dom = wheel.dom || {};
    wheel.dom.observe = function(selector, callback) {
        const target = document.querySelector(selector) || document.body;
        const observer = new MutationObserver(mutations => {
            callback(mutations.map(m => ({
                type: m.type,
                addedNodes: m.addedNodes.length,
                removedNodes: m.removedNodes.length
            })));
        });
        observer.observe(target, { childList: true, subtree: true });
        return { disconnect: () => observer.disconnect() };
    };
    """

    private static func storageAPI(moduleId: UUID) -> String {
        let prefix = "wheel_module_\(moduleId.uuidString)_"
        return """
        wheel.storage = {
            async get(key) {
                const raw = localStorage.getItem('\(prefix)' + key);
                if (raw === null) return null;
                try { return JSON.parse(raw); } catch { return raw; }
            },
            async set(key, value) {
                // 512KB total quota enforcement
                const prefix = '\(prefix)';
                let total = 0;
                for (let i = 0; i < localStorage.length; i++) {
                    const k = localStorage.key(i);
                    if (k && k.startsWith(prefix)) {
                        total += (localStorage.getItem(k) || '').length;
                    }
                }
                const newVal = JSON.stringify(value);
                if (total + newVal.length > 524288) {
                    throw new Error('Storage quota exceeded (512KB)');
                }
                localStorage.setItem(prefix + key, newVal);
            },
            async remove(key) {
                localStorage.removeItem('\(prefix)' + key);
            }
        };
        """
    }

    private static func messagingAPI(moduleId: UUID) -> String {
        """
        wheel.message = {
            _handlers: {},
            send(type, data) {
                window.webkit?.messageHandlers?.wheelModuleMessage?.postMessage({
                    moduleId: '\(moduleId.uuidString)',
                    type: type,
                    data: data
                });
            },
            on(type, callback) {
                if (!this._handlers[type]) this._handlers[type] = [];
                this._handlers[type].push(callback);
            },
            _dispatch(type, data) {
                (this._handlers[type] || []).forEach(cb => cb(data));
            }
        };
        """
    }

    private static let resultAPI = """
    wheel.result = function(data) {
        window.webkit?.messageHandlers?.wheelModuleResult?.postMessage({
            data: data
        });
    };
    """
}
