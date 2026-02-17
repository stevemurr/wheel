import Foundation

// MARK: - Blocking Categories

/// Categories of content blocking rules that can be individually enabled/disabled
enum BlockingCategory: String, CaseIterable, Codable {
    case ads = "ads"
    case trackers = "trackers"
    case socialWidgets = "social"
    case annoyances = "annoyances"

    var displayName: String {
        switch self {
        case .ads: return "Ads"
        case .trackers: return "Trackers"
        case .socialWidgets: return "Social Widgets"
        case .annoyances: return "Annoyances"
        }
    }

    var description: String {
        switch self {
        case .ads:
            return "Block advertisements from major ad networks"
        case .trackers:
            return "Block analytics and tracking scripts"
        case .socialWidgets:
            return "Block social media widgets and share buttons"
        case .annoyances:
            return "Block cookie banners, newsletter popups, and other annoyances"
        }
    }

    var icon: String {
        switch self {
        case .ads: return "rectangle.slash"
        case .trackers: return "eye.slash"
        case .socialWidgets: return "person.2.slash"
        case .annoyances: return "xmark.rectangle"
        }
    }
}

// MARK: - Blocking Rules

/// Content blocking rules in WebKit's JSON format
/// Reference: https://developer.apple.com/documentation/safariservices/creating_a_content_blocker
///
/// Rule Structure:
/// - trigger: Defines when the rule applies (url-filter, resource-type, load-type, if-domain, unless-domain)
/// - action: What to do when triggered (block, block-cookies, css-display-none, ignore-previous-rules)
///
/// URL Filter Syntax:
/// - Uses regular expressions
/// - ".*" matches any string
/// - Escape dots as "\\\\." (double-escaped for Swift string + JSON)
/// - Case insensitive by default
struct BlockingRules {

    /// Rule set identifier for WebKit's cache
    static let ruleSetIdentifier = "WheelBrowserBlockingRules"

    /// Version for cache invalidation - increment when rules change
    static let ruleSetVersion = "2.0.0"

    // MARK: - Rule Generation

    /// Generates combined JSON rules for the specified categories
    /// - Parameter categories: Set of categories to include
    /// - Returns: JSON string of combined rules
    static func generateRulesJSON(for categories: Set<BlockingCategory>) -> String {
        var allRules: [[String: Any]] = []

        for category in categories {
            allRules.append(contentsOf: rules(for: category))
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: allRules, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "[]"
        }

        return jsonString
    }

    /// Returns rules for a specific category
    private static func rules(for category: BlockingCategory) -> [[String: Any]] {
        switch category {
        case .ads:
            return adBlockingRules
        case .trackers:
            return trackerBlockingRules
        case .socialWidgets:
            return socialWidgetRules
        case .annoyances:
            return annoyanceRules
        }
    }

    /// Default rules JSON (all categories enabled)
    static var defaultRulesJSON: String {
        generateRulesJSON(for: Set(BlockingCategory.allCases))
    }

    // MARK: - Ad Blocking Rules

    /// Rules for blocking advertisements
    /// Covers major ad networks, programmatic advertising, and native advertising
    private static var adBlockingRules: [[String: Any]] {
        return [
            // ========================================
            // GOOGLE ADS ECOSYSTEM
            // ========================================

            // Google Ads - Third-party scripts
            [
                "trigger": [
                    "url-filter": ".*",
                    "resource-type": ["script"],
                    "load-type": ["third-party"],
                    "if-domain": ["*doubleclick.net", "*googlesyndication.com", "*googleadservices.com", "*googletagservices.com"]
                ],
                "action": ["type": "block"]
            ],
            // Google Ads - All resources
            [
                "trigger": [
                    "url-filter": ".*",
                    "resource-type": ["script", "image", "style-sheet", "raw"],
                    "if-domain": ["*adservice.google.com", "*ads.google.com", "*pagead2.googlesyndication.com"]
                ],
                "action": ["type": "block"]
            ],
            // DoubleClick
            [
                "trigger": ["url-filter": ".*\\.doubleclick\\.net"],
                "action": ["type": "block"]
            ],
            // Google Syndication
            [
                "trigger": ["url-filter": ".*\\.googlesyndication\\.com"],
                "action": ["type": "block"]
            ],
            // Google Ad Services
            [
                "trigger": ["url-filter": ".*\\.googleadservices\\.com"],
                "action": ["type": "block"]
            ],
            // 2mdn (Google subsidiary)
            [
                "trigger": ["url-filter": ".*\\.2mdn\\.net"],
                "action": ["type": "block"]
            ],

            // ========================================
            // PROGRAMMATIC ADVERTISING / DSPs / SSPs
            // ========================================

            // AppNexus (Xandr)
            [
                "trigger": ["url-filter": ".*\\.adnxs\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.adnxs-simple\\.com"],
                "action": ["type": "block"]
            ],
            // The Trade Desk
            [
                "trigger": ["url-filter": ".*\\.adsrvr\\.org"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.thetradedesk\\.com"],
                "action": ["type": "block"]
            ],
            // Criteo
            [
                "trigger": ["url-filter": ".*\\.criteo\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.criteo\\.net"],
                "action": ["type": "block"]
            ],
            // Rubicon Project (Magnite)
            [
                "trigger": ["url-filter": ".*\\.rubiconproject\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.rubiconproject\\.net"],
                "action": ["type": "block"]
            ],
            // PubMatic
            [
                "trigger": ["url-filter": ".*\\.pubmatic\\.com"],
                "action": ["type": "block"]
            ],
            // OpenX
            [
                "trigger": ["url-filter": ".*\\.openx\\.net"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.openx\\.com"],
                "action": ["type": "block"]
            ],
            // Index Exchange
            [
                "trigger": ["url-filter": ".*\\.indexexchange\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.casalemedia\\.com"],
                "action": ["type": "block"]
            ],
            // MediaMath
            [
                "trigger": ["url-filter": ".*\\.mathtag\\.com"],
                "action": ["type": "block"]
            ],
            // Sizmek (Amazon)
            [
                "trigger": ["url-filter": ".*\\.serving-sys\\.com"],
                "action": ["type": "block"]
            ],
            // TripleLift
            [
                "trigger": ["url-filter": ".*\\.triplelift\\.com"],
                "action": ["type": "block"]
            ],
            // Verizon Media / Yahoo
            [
                "trigger": ["url-filter": ".*\\.advertising\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.adtech\\.advertising\\.com"],
                "action": ["type": "block"]
            ],
            // Sharethrough
            [
                "trigger": ["url-filter": ".*\\.sharethrough\\.com"],
                "action": ["type": "block"]
            ],
            // Sovrn
            [
                "trigger": ["url-filter": ".*\\.lijit\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.sovrn\\.com"],
                "action": ["type": "block"]
            ],
            // 33Across
            [
                "trigger": ["url-filter": ".*\\.33across\\.com"],
                "action": ["type": "block"]
            ],
            // GumGum
            [
                "trigger": ["url-filter": ".*\\.gumgum\\.com"],
                "action": ["type": "block"]
            ],
            // Teads
            [
                "trigger": ["url-filter": ".*\\.teads\\.tv"],
                "action": ["type": "block"]
            ],
            // SpotX
            [
                "trigger": ["url-filter": ".*\\.spotxchange\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.spotx\\.tv"],
                "action": ["type": "block"]
            ],
            // Undertone
            [
                "trigger": ["url-filter": ".*\\.undertone\\.com"],
                "action": ["type": "block"]
            ],
            // Conversant
            [
                "trigger": ["url-filter": ".*\\.conversantmedia\\.com"],
                "action": ["type": "block"]
            ],
            // AdColony
            [
                "trigger": ["url-filter": ".*\\.adcolony\\.com"],
                "action": ["type": "block"]
            ],
            // Vungle
            [
                "trigger": ["url-filter": ".*\\.vungle\\.com"],
                "action": ["type": "block"]
            ],
            // Unity Ads
            [
                "trigger": ["url-filter": ".*\\.unityads\\.unity3d\\.com"],
                "action": ["type": "block"]
            ],
            // IronSource
            [
                "trigger": ["url-filter": ".*\\.ironsrc\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // NATIVE ADVERTISING / CONTENT RECOMMENDATION
            // ========================================

            // Taboola
            [
                "trigger": ["url-filter": ".*\\.taboola\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.taboolasyndication\\.com"],
                "action": ["type": "block"]
            ],
            // Outbrain
            [
                "trigger": ["url-filter": ".*\\.outbrain\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.outbrainimg\\.com"],
                "action": ["type": "block"]
            ],
            // RevContent
            [
                "trigger": ["url-filter": ".*\\.revcontent\\.com"],
                "action": ["type": "block"]
            ],
            // MGID
            [
                "trigger": ["url-filter": ".*\\.mgid\\.com"],
                "action": ["type": "block"]
            ],
            // Content.ad
            [
                "trigger": ["url-filter": ".*\\.content\\.ad"],
                "action": ["type": "block"]
            ],
            // Nativo
            [
                "trigger": ["url-filter": ".*\\.nativo\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.ntv\\.io"],
                "action": ["type": "block"]
            ],
            // Zergnet
            [
                "trigger": ["url-filter": ".*\\.zergnet\\.com"],
                "action": ["type": "block"]
            ],
            // Yahoo Gemini
            [
                "trigger": ["url-filter": ".*\\.gemini\\.yahoo\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // AMAZON ADVERTISING
            // ========================================

            [
                "trigger": ["url-filter": ".*\\.amazon-adsystem\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.amazonservices\\.com/widgets"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*assoc-amazon\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // AD NETWORKS - GENERAL
            // ========================================

            // AdForm
            [
                "trigger": ["url-filter": ".*\\.adform\\.net"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.adform\\.com"],
                "action": ["type": "block"]
            ],
            // SmartAdServer
            [
                "trigger": ["url-filter": ".*\\.smartadserver\\.com"],
                "action": ["type": "block"]
            ],
            // ZEDO
            [
                "trigger": ["url-filter": ".*\\.zedo\\.com"],
                "action": ["type": "block"]
            ],
            // Media.net
            [
                "trigger": ["url-filter": ".*\\.media\\.net"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.medianet\\.com"],
                "action": ["type": "block"]
            ],
            // BuySellAds
            [
                "trigger": ["url-filter": ".*\\.buysellads\\.com"],
                "action": ["type": "block"]
            ],
            // Carbon Ads
            [
                "trigger": ["url-filter": ".*\\.carbonads\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.carbonads\\.net"],
                "action": ["type": "block"]
            ],
            // AdRoll
            [
                "trigger": ["url-filter": ".*\\.adroll\\.com"],
                "action": ["type": "block"]
            ],
            // Bidswitch
            [
                "trigger": ["url-filter": ".*\\.bidswitch\\.net"],
                "action": ["type": "block"]
            ],
            // AdKernel
            [
                "trigger": ["url-filter": ".*\\.adkernel\\.com"],
                "action": ["type": "block"]
            ],
            // Yieldmo
            [
                "trigger": ["url-filter": ".*\\.yieldmo\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // POP-UP / POP-UNDER ADS
            // ========================================

            // PopAds
            [
                "trigger": ["url-filter": ".*\\.popads\\.net"],
                "action": ["type": "block"]
            ],
            // PopCash
            [
                "trigger": ["url-filter": ".*\\.popcash\\.net"],
                "action": ["type": "block"]
            ],
            // PropellerAds
            [
                "trigger": ["url-filter": ".*\\.propellerads\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.propellerclick\\.com"],
                "action": ["type": "block"]
            ],
            // AdCash
            [
                "trigger": ["url-filter": ".*\\.adcash\\.com"],
                "action": ["type": "block"]
            ],
            // TrafficFactory
            [
                "trigger": ["url-filter": ".*\\.trafficfactory\\.biz"],
                "action": ["type": "block"]
            ],

            // ========================================
            // VIDEO AD NETWORKS
            // ========================================

            // FreeWheel
            [
                "trigger": ["url-filter": ".*\\.fwmrm\\.net"],
                "action": ["type": "block"]
            ],
            // JW Player Ads
            [
                "trigger": ["url-filter": ".*\\.jwpcdn\\.com/.*vast"],
                "action": ["type": "block"]
            ],
            // BrightRoll
            [
                "trigger": ["url-filter": ".*\\.brightroll\\.com"],
                "action": ["type": "block"]
            ],
            // Tremor Video
            [
                "trigger": ["url-filter": ".*\\.tremorhub\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // AFFILIATE NETWORKS
            // ========================================

            // Commission Junction
            [
                "trigger": ["url-filter": ".*\\.dpbolvw\\.net"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.anrdoezrs\\.net"],
                "action": ["type": "block"]
            ],
            // ShareASale
            [
                "trigger": ["url-filter": ".*\\.shareasale\\.com/r\\.cfm"],
                "action": ["type": "block"]
            ],
            // Skimlinks
            [
                "trigger": ["url-filter": ".*\\.skimresources\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.skimlinks\\.com"],
                "action": ["type": "block"]
            ],
            // VigLink
            [
                "trigger": ["url-filter": ".*\\.viglink\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // CSS HIDING - AD CONTAINERS
            // ========================================

            // Common ad class names
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".ad, .ads, .advertisement, .ad-banner, .ad-container, .ad-wrapper, .ad-unit, .advert, .advertising, .adbox, .adsbox, .ad-slot, .ad-space"
                ]
            ],
            // Ad position classes
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".ad-leaderboard, .ad-sidebar, .ad-footer, .ad-header, .ad-top, .ad-bottom, .ad-left, .ad-right, .ad-middle, .ad-inline, .ad-native"
                ]
            ],
            // Google Ads specific
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": "[id*='google_ads'], [id*='GoogleAds'], [id*='googleAds'], [class*='google-ad'], ins.adsbygoogle, amp-ad, amp-embed, amp-sticky-ad"
                ]
            ],
            // GPT/DFP ads
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": "[id^='div-gpt-ad'], [id*='dfp-ad'], .dfp-ad, .gpt-ad, [data-google-query-id], [data-ad-slot], [data-ad-client]"
                ]
            ],
            // Generic ad attributes
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": "[id*='ad-'], [id*='_ad_'], [id*='ad_'], [class*='ad-unit'], [class*='adUnit'], [data-ad], [data-ad-type]"
                ]
            ],
            // Sponsored content
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".sponsored, .sponsored-content, .sponsored-post, .promoted-content, .promoted-post, .native-ad, .partner-content, .paid-content, .branded-content"
                ]
            ],
            // Taboola/Outbrain widgets
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".taboola, .trc_rbox, .trc_related_container, #taboola-below-article, #taboola-right-rail, .OUTBRAIN, .outbrain-widget, [data-widget-type='taboola'], [data-widget-type='outbrain']"
                ]
            ],
            // RevContent/MGID widgets
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".rc-widget, [id^='rc-widget'], .mgid-container, [id^='mgid'], [data-rcwidget]"
                ]
            ],
            // Sticky/floating ads
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".sticky-ad, .floating-ad, .adhesion-ad, .anchor-ad, [class*='sticky-ad'], [class*='floating-ad'], [id*='sticky-ad']"
                ]
            ]
        ]
    }

    // MARK: - Tracker Blocking Rules

    /// Rules for blocking analytics and tracking scripts
    private static var trackerBlockingRules: [[String: Any]] {
        return [
            // ========================================
            // GOOGLE ANALYTICS & TAG MANAGER
            // ========================================

            [
                "trigger": ["url-filter": ".*\\.google-analytics\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.googletagmanager\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*analytics\\.google\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.googleoptimize\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // MEASUREMENT & VERIFICATION
            // ========================================

            // comScore / Scorecard Research
            [
                "trigger": ["url-filter": ".*\\.scorecardresearch\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.comscore\\.com"],
                "action": ["type": "block"]
            ],
            // Moat (Oracle)
            [
                "trigger": ["url-filter": ".*\\.moatads\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.moatpixel\\.com"],
                "action": ["type": "block"]
            ],
            // Quantcast
            [
                "trigger": ["url-filter": ".*\\.quantserve\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.quantcount\\.com"],
                "action": ["type": "block"]
            ],
            // Nielsen
            [
                "trigger": ["url-filter": ".*\\.imrworldwide\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.nielsen\\.com/.*pixel"],
                "action": ["type": "block"]
            ],
            // DoubleVerify
            [
                "trigger": ["url-filter": ".*\\.doubleverify\\.com"],
                "action": ["type": "block"]
            ],
            // IAS (Integral Ad Science)
            [
                "trigger": ["url-filter": ".*\\.adsafeprotected\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // DATA MANAGEMENT PLATFORMS (DMPs)
            // ========================================

            // BlueKai (Oracle)
            [
                "trigger": ["url-filter": ".*\\.bluekai\\.com"],
                "action": ["type": "block"]
            ],
            // Exelate
            [
                "trigger": ["url-filter": ".*\\.exelator\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.exelate\\.com"],
                "action": ["type": "block"]
            ],
            // Lotame
            [
                "trigger": ["url-filter": ".*\\.crwdcntrl\\.net"],
                "action": ["type": "block"]
            ],
            // Neustar
            [
                "trigger": ["url-filter": ".*\\.agkn\\.com"],
                "action": ["type": "block"]
            ],
            // Liveramp
            [
                "trigger": ["url-filter": ".*\\.rlcdn\\.com"],
                "action": ["type": "block"]
            ],
            // OnAudience
            [
                "trigger": ["url-filter": ".*\\.onaudience\\.com"],
                "action": ["type": "block"]
            ],
            // Eyeota
            [
                "trigger": ["url-filter": ".*\\.eyeota\\.net"],
                "action": ["type": "block"]
            ],

            // ========================================
            // PRODUCT ANALYTICS
            // ========================================

            // Hotjar
            [
                "trigger": ["url-filter": ".*\\.hotjar\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.hotjar\\.io"],
                "action": ["type": "block"]
            ],
            // Mixpanel
            [
                "trigger": ["url-filter": ".*\\.mixpanel\\.com"],
                "action": ["type": "block"]
            ],
            // Amplitude
            [
                "trigger": ["url-filter": ".*\\.amplitude\\.com"],
                "action": ["type": "block"]
            ],
            // Segment
            [
                "trigger": ["url-filter": ".*\\.segment\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.segment\\.io"],
                "action": ["type": "block"]
            ],
            // Heap
            [
                "trigger": ["url-filter": ".*\\.heapanalytics\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.heap\\.io"],
                "action": ["type": "block"]
            ],
            // FullStory
            [
                "trigger": ["url-filter": ".*\\.fullstory\\.com"],
                "action": ["type": "block"]
            ],
            // LogRocket
            [
                "trigger": ["url-filter": ".*\\.logrocket\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.logrocket\\.io"],
                "action": ["type": "block"]
            ],
            // Pendo
            [
                "trigger": ["url-filter": ".*\\.pendo\\.io"],
                "action": ["type": "block"]
            ],
            // Kissmetrics
            [
                "trigger": ["url-filter": ".*\\.kissmetrics\\.com"],
                "action": ["type": "block"]
            ],
            // Mouseflow
            [
                "trigger": ["url-filter": ".*\\.mouseflow\\.com"],
                "action": ["type": "block"]
            ],
            // Crazy Egg
            [
                "trigger": ["url-filter": ".*\\.crazyegg\\.com"],
                "action": ["type": "block"]
            ],
            // Lucky Orange
            [
                "trigger": ["url-filter": ".*\\.luckyorange\\.com"],
                "action": ["type": "block"]
            ],
            // Inspectlet
            [
                "trigger": ["url-filter": ".*\\.inspectlet\\.com"],
                "action": ["type": "block"]
            ],
            // VWO
            [
                "trigger": ["url-filter": ".*\\.visualwebsiteoptimizer\\.com"],
                "action": ["type": "block"]
            ],
            // Optimizely
            [
                "trigger": ["url-filter": ".*\\.optimizely\\.com"],
                "action": ["type": "block"]
            ],
            // AB Tasty
            [
                "trigger": ["url-filter": ".*\\.abtasty\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // CUSTOMER DATA / ATTRIBUTION
            // ========================================

            // Adjust
            [
                "trigger": ["url-filter": ".*\\.adjust\\.com"],
                "action": ["type": "block"]
            ],
            // AppsFlyer
            [
                "trigger": ["url-filter": ".*\\.appsflyer\\.com"],
                "action": ["type": "block"]
            ],
            // Branch
            [
                "trigger": ["url-filter": ".*\\.branch\\.io"],
                "action": ["type": "block"]
            ],
            // Singular
            [
                "trigger": ["url-filter": ".*\\.singular\\.net"],
                "action": ["type": "block"]
            ],
            // Kochava
            [
                "trigger": ["url-filter": ".*\\.kochava\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // FINGERPRINTING / FRAUD DETECTION
            // ========================================

            // FingerprintJS
            [
                "trigger": ["url-filter": ".*\\.fpjs\\.io"],
                "action": ["type": "block"]
            ],
            // ThreatMetrix
            [
                "trigger": ["url-filter": ".*\\.online-metrix\\.net"],
                "action": ["type": "block"]
            ],
            // PerimeterX
            [
                "trigger": ["url-filter": ".*\\.perimeterx\\.net"],
                "action": ["type": "block"]
            ],
            // Iovation
            [
                "trigger": ["url-filter": ".*\\.iovation\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // TAG MANAGEMENT / CDP
            // ========================================

            // Tealium
            [
                "trigger": ["url-filter": ".*\\.tealiumiq\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.tiqcdn\\.com"],
                "action": ["type": "block"]
            ],
            // Ensighten
            [
                "trigger": ["url-filter": ".*\\.ensighten\\.com"],
                "action": ["type": "block"]
            ],
            // Signal (BrightTag)
            [
                "trigger": ["url-filter": ".*\\.thebrighttag\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // OTHER TRACKERS
            // ========================================

            // New Relic (browser monitoring)
            [
                "trigger": ["url-filter": ".*bam\\.nr-data\\.net"],
                "action": ["type": "block"]
            ],
            // Sentry (error tracking - optional, can be useful)
            // Commented out as some sites depend on this for functionality
            // [
            //     "trigger": ["url-filter": ".*\\.sentry\\.io"],
            //     "action": ["type": "block"]
            // ],
            // Bugsnag
            [
                "trigger": ["url-filter": ".*\\.bugsnag\\.com"],
                "action": ["type": "block"]
            ],
            // TrackJS
            [
                "trigger": ["url-filter": ".*\\.trackjs\\.com"],
                "action": ["type": "block"]
            ]
        ]
    }

    // MARK: - Social Widget Rules

    /// Rules for blocking social media widgets and tracking pixels
    private static var socialWidgetRules: [[String: Any]] {
        return [
            // ========================================
            // FACEBOOK / META
            // ========================================

            // Facebook Pixel
            [
                "trigger": ["url-filter": ".*\\.facebook\\.com/tr"],
                "action": ["type": "block"]
            ],
            // Facebook Events
            [
                "trigger": ["url-filter": ".*connect\\.facebook\\.net.*fbevents"],
                "action": ["type": "block"]
            ],
            // Facebook SDK (tracking components)
            [
                "trigger": ["url-filter": ".*connect\\.facebook\\.net.*sdk"],
                "action": ["type": "block"]
            ],
            // Facebook Widgets
            [
                "trigger": ["url-filter": ".*\\.facebook\\.com/plugins"],
                "action": ["type": "block"]
            ],

            // ========================================
            // TWITTER / X
            // ========================================

            // Twitter Pixel
            [
                "trigger": ["url-filter": ".*\\.twitter\\.com/i/adsct"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.t\\.co/i/adsct"],
                "action": ["type": "block"]
            ],
            // Twitter Analytics
            [
                "trigger": ["url-filter": ".*analytics\\.twitter\\.com"],
                "action": ["type": "block"]
            ],
            // Twitter Widgets
            [
                "trigger": ["url-filter": ".*platform\\.twitter\\.com/widgets"],
                "action": ["type": "block"]
            ],

            // ========================================
            // LINKEDIN
            // ========================================

            // LinkedIn Insight Tag
            [
                "trigger": ["url-filter": ".*\\.linkedin\\.com/px"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*snap\\.licdn\\.com"],
                "action": ["type": "block"]
            ],
            // LinkedIn Tracking
            [
                "trigger": ["url-filter": ".*\\.linkedin\\.com/li/track"],
                "action": ["type": "block"]
            ],

            // ========================================
            // TIKTOK
            // ========================================

            [
                "trigger": ["url-filter": ".*\\.tiktok\\.com/i/.*pixel"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*analytics\\.tiktok\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // PINTEREST
            // ========================================

            [
                "trigger": ["url-filter": ".*\\.pinimg\\.com.*ct\\.js"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*ct\\.pinterest\\.com"],
                "action": ["type": "block"]
            ],

            // ========================================
            // SNAPCHAT
            // ========================================

            [
                "trigger": ["url-filter": ".*tr\\.snapchat\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.sc-static\\.net.*scevent"],
                "action": ["type": "block"]
            ],

            // ========================================
            // REDDIT
            // ========================================

            [
                "trigger": ["url-filter": ".*\\.redditstatic\\.com.*pixel"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*redditmedia\\.com/pixel"],
                "action": ["type": "block"]
            ],

            // ========================================
            // MICROSOFT / BING
            // ========================================

            [
                "trigger": ["url-filter": ".*\\.bing\\.com/action"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*bat\\.bing\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.clarity\\.ms"],
                "action": ["type": "block"]
            ],

            // ========================================
            // QUORA
            // ========================================

            [
                "trigger": ["url-filter": ".*\\.quora\\.com/_/ad"],
                "action": ["type": "block"]
            ],

            // ========================================
            // CSS HIDING - SOCIAL WIDGETS
            // ========================================

            // Facebook widgets
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".fb-like, .fb-share-button, .fb-comments, .fb-page, .fb-follow, .fb-send, [class*='facebook-widget'], [class*='fb-widget']"
                ]
            ],
            // Twitter widgets
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".twitter-tweet, .twitter-timeline, .twitter-share-button, .twitter-follow-button, [class*='twitter-widget']"
                ]
            ],
            // General social share buttons
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".social-share, .share-buttons, .social-buttons, .share-bar, .social-icons, [class*='social-share'], [class*='share-button']"
                ]
            ],
            // AddThis / ShareThis
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".addthis_toolbox, .addthis-smartlayers, #at-share-dock, .sharethis-inline-share-buttons, [class*='addthis'], [class*='sharethis']"
                ]
            ]
        ]
    }

    // MARK: - Annoyance Rules

    /// Rules for blocking cookie banners, newsletter popups, and other annoyances
    private static var annoyanceRules: [[String: Any]] {
        return [
            // ========================================
            // COOKIE CONSENT / GDPR BANNERS
            // ========================================

            // Consent Management Platforms
            [
                "trigger": ["url-filter": ".*\\.cookielaw\\.org"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.onetrust\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.trustarc\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.cookiebot\\.com"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.consensu\\.org"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.privacymanager\\.io"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.quantcast\\.mgr\\.consensu\\.org"],
                "action": ["type": "block"]
            ],

            // CSS Hiding - Cookie Banners
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": "#cookie-banner, #cookie-consent, #cookie-notice, #cookie-popup, #cookie-modal, #cookie-law-info-bar, #cookie-policy"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".cookie-banner, .cookie-consent, .cookie-notice, .cookie-popup, .cookie-modal, .cookie-bar, .cookie-alert, .cookie-warning"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": "[class*='CookieConsent'], [class*='cookieConsent'], [class*='cookie-consent'], [class*='cookie_consent']"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".gdpr-banner, .gdpr-consent, .gdpr-notice, .gdpr-popup, #gdpr-banner, #gdpr-consent, [class*='gdpr-']"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".consent-banner, .consent-popup, .consent-modal, #consent-banner, #consent-popup, [class*='consent-banner']"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": "#onetrust-banner-sdk, #onetrust-consent-sdk, .onetrust-pc-dark-filter, #truste-consent-track"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": "#CybotCookiebotDialog, #CybotCookiebotDialogBodyLevelButtonLevelOptinAllowallSelection"
                ]
            ],

            // ========================================
            // NEWSLETTER / EMAIL POPUPS
            // ========================================

            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".newsletter-popup, .newsletter-modal, .newsletter-overlay, #newsletter-popup, #newsletter-modal"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".email-signup-popup, .email-popup, .email-modal, .email-capture, .signup-popup, .signup-modal"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".subscription-popup, .subscribe-popup, .subscribe-modal, #subscribe-popup, #subscription-modal"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": "[class*='newsletter-popup'], [class*='email-popup'], [class*='signup-popup'], [id*='newsletter-popup']"
                ]
            ],

            // ========================================
            // NOTIFICATION / PUSH PROMPTS
            // ========================================

            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".push-notification-prompt, .notification-prompt, .push-prompt, #push-notification, [class*='push-notification']"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".browser-notification-prompt, .notification-permission, .notify-prompt"
                ]
            ],

            // ========================================
            // CHAT WIDGETS
            // ========================================

            // Intercom
            [
                "trigger": ["url-filter": ".*\\.intercom\\.io"],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*\\.intercomcdn\\.com"],
                "action": ["type": "block"]
            ],
            // Drift
            [
                "trigger": ["url-filter": ".*\\.drift\\.com"],
                "action": ["type": "block"]
            ],
            // Zendesk Chat
            [
                "trigger": ["url-filter": ".*\\.zopim\\.com"],
                "action": ["type": "block"]
            ],
            // LiveChat
            [
                "trigger": ["url-filter": ".*\\.livechatinc\\.com"],
                "action": ["type": "block"]
            ],
            // Crisp
            [
                "trigger": ["url-filter": ".*\\.crisp\\.chat"],
                "action": ["type": "block"]
            ],
            // Tawk.to
            [
                "trigger": ["url-filter": ".*\\.tawk\\.to"],
                "action": ["type": "block"]
            ],
            // Olark
            [
                "trigger": ["url-filter": ".*\\.olark\\.com"],
                "action": ["type": "block"]
            ],
            // Freshchat
            [
                "trigger": ["url-filter": ".*\\.freshchat\\.com"],
                "action": ["type": "block"]
            ],
            // HubSpot Chat
            [
                "trigger": ["url-filter": ".*\\.hs-scripts\\.com"],
                "action": ["type": "block"]
            ],

            // CSS Hiding - Chat widgets
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": "#intercom-container, .intercom-launcher, .intercom-lightweight-app, #drift-widget, #drift-frame"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".zopim, #launcher, .livechat-widget, [class*='crisp-client'], #tawk-chat-widget"
                ]
            ],

            // ========================================
            // SURVEY / FEEDBACK WIDGETS
            // ========================================

            // Qualtrics
            [
                "trigger": ["url-filter": ".*\\.qualtrics\\.com"],
                "action": ["type": "block"]
            ],
            // SurveyMonkey
            [
                "trigger": ["url-filter": ".*\\.surveymonkey\\.com/collect"],
                "action": ["type": "block"]
            ],
            // Medallia
            [
                "trigger": ["url-filter": ".*\\.medallia\\.com"],
                "action": ["type": "block"]
            ],
            // UserVoice
            [
                "trigger": ["url-filter": ".*\\.uservoice\\.com"],
                "action": ["type": "block"]
            ],
            // Usabilla
            [
                "trigger": ["url-filter": ".*\\.usabilla\\.com"],
                "action": ["type": "block"]
            ],

            // CSS Hiding - Survey popups
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".survey-popup, .feedback-popup, .survey-modal, .feedback-modal, [class*='survey-'], [class*='feedback-prompt']"
                ]
            ],

            // ========================================
            // PAYWALL / SUBSCRIPTION NAG
            // ========================================

            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".paywall-banner, .subscription-banner, .subscribe-banner, .premium-banner, [class*='paywall-'], [class*='subscription-nag']"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".meter-bar, .article-meter, .metering-banner, [class*='meter-banner'], [class*='article-limit']"
                ]
            ],

            // ========================================
            // APP INSTALL BANNERS
            // ========================================

            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".app-banner, .app-install-banner, .smart-banner, .smartbanner, #smart-app-banner, [class*='app-banner'], [class*='install-app']"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".mobile-app-banner, .download-app-banner, [class*='download-app'], [class*='get-app']"
                ]
            ],

            // ========================================
            // OVERLAY / MODAL ANNOYANCES
            // ========================================

            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".modal-backdrop:empty, .overlay-backdrop:empty, .page-overlay:empty"
                ]
            ],
            [
                "trigger": ["url-filter": ".*", "if-domain": ["*"]],
                "action": [
                    "type": "css-display-none",
                    "selector": ".exit-intent-popup, .exit-popup, [class*='exit-intent'], [class*='exit-popup']"
                ]
            ]
        ]
    }
}
