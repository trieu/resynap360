// (1) LEO OBSERVER: load JavaScript code for [LEO CHATBOT]
(function () {
  // Observer ID
  // TODO
  window.leoObserverId = "";
  window.leoObserverLogDomain = "";
  window.leoObserverCdnDomain = "";

  // Data Touchpoint Metadata
  window.srcTouchpointName = encodeURIComponent(document.title);
  window.srcTouchpointUrl = encodeURIComponent(location.href);

  // the main proxy LEO JS
  var leoproxyJsPath = "/js/leo-observer/leo.proxy.min.js";
  var src =
    location.protocol + "//" + window.leoObserverCdnDomain + leoproxyJsPath;
  var jsNode = document.createElement("script");
  jsNode.async = true;
  jsNode.defer = true;
  jsNode.src = src;
  var s = document.getElementsByTagName("script")[0];
  s.parentNode.insertBefore(jsNode, s);
})();

var parseDataUTM =
  window.parseDataUTM ||
  function () {
    if (location.search.indexOf("utm_") > 0) {
      var search = location.search.substring(1);
      var json = decodeURI(search)
        .replace(/"/g, '\\"')
        .replace(/&/g, '","')
        .replace(/=/g, '":"');
      return JSON.parse('{"' + json + '"}');
    }
  };

// (2) LEO OBSERVER: set-up all event tracking functions
var LeoObserver = {};

// (2.1) function to track View Event "AdImpression"
LeoObserver.recordEventAdImpression = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordViewEvent("ad-impression", eventData);
};

// (2.2) function to track View Event "PageView"
LeoObserver.recordEventPageView = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordViewEvent("page-view", eventData);
};

// (2.3) function to track View Event "AcceptTracking"
LeoObserver.recordEventAcceptTracking = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordViewEvent("accept-tracking", eventData);
};

// (2.4) function to track View Event "EngagedSession"
LeoObserver.recordEventEngagedSession = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordViewEvent("engaged-session", eventData);
};

// (2.5) function to track Action Event "Like"
LeoObserver.recordEventLike = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("like", eventData);
};

// (2.6) function to track View Event "ContentView"
LeoObserver.recordEventContentView = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordViewEvent("content-view", eventData);
};

// (2.7) function to track Action Event "Search"
LeoObserver.recordEventSearch = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("search", eventData);
};

// (2.8) function to track View Event "ItemView"
LeoObserver.recordEventItemView = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordViewEvent("item-view", eventData);
};

// (2.9) function to track Action Event "ClickDetails"
LeoObserver.recordEventClickDetails = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("click-details", eventData);
};

// (2.10) function to track Action Event "PlayVideo"
LeoObserver.recordEventPlayVideo = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("play-video", eventData);
};

// (2.11) function to track Action Event "SubmitContact"
LeoObserver.recordEventSubmitContact = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("submit-contact", eventData);
};

// (2.12) function to track Action Event "FileDownload"
LeoObserver.recordEventFileDownload = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("file-download", eventData);
};

// (2.13) function to track Action Event "RegisterAccount"
LeoObserver.recordEventRegisterAccount = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("register-account", eventData);
};

// (2.14) function to track Action Event "UserLogin"
LeoObserver.recordEventUserLogin = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("user-login", eventData);
};

// (2.15) function to track Action Event "ShortLinkClick"
LeoObserver.recordEventShortLinkClick = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("short-link-click", eventData);
};

// (2.16) function to track Action Event "AskQuestion"
LeoObserver.recordEventAskQuestion = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("ask-question", eventData);
};

// (2.17) function to track Action Event "ProductTrial"
LeoObserver.recordEventProductTrial = function (eventData) {
  eventData = eventData ? eventData : {};
  LeoObserverProxy.recordActionEvent("product-trial", eventData);
};

// (2.18) function to track Conversion Event "Purchase"
LeoObserver.recordEventPurchase = function (
  eventData,
  shoppingCartItems,
  transactionId,
  transactionValue,
  currencyCode
) {
  // need 5 params
  eventData = typeof eventData === "object" ? eventData : {};
  shoppingCartItems =
    typeof shoppingCartItems === "object" ? shoppingCartItems : [];
  transactionId = typeof transactionId === "string" ? transactionId : "";
  transactionValue =
    typeof transactionValue === "number" ? transactionValue : 0;
  currencyCode = typeof currencyCode === "string" ? currencyCode : "USD";

  LeoObserverProxy.recordConversionEvent(
    "purchase",
    eventData,
    transactionId,
    shoppingCartItems,
    transactionValue,
    currencyCode
  );
};

// (3) LEO OBSERVER is ready
function leoObserverProxyReady(session) {
  // auto tracking when CDP JS is ready
  LeoObserver.recordEventPageView();

  // set tracking LEO visitor ID into all a[href] nodes
  LeoObserverProxy.synchLeoVisitorId(function (vid) {
    var aNodes = document.querySelectorAll("a");
    [].forEach.call(aNodes, function (aNode) {
      var hrefUrl = aNode.href || "";
      var check =
        hrefUrl.indexOf("http") >= 0 && hrefUrl.indexOf(location.host) < 0;
      if (check) {
        if (hrefUrl.indexOf("?") > 0) hrefUrl += "&leosyn=" + vid;
        else hrefUrl += "?leosyn=" + vid;
        aNode.href = hrefUrl;
      }
    });
    if (typeof window.synchLeoCdpToGA4 === "function") {
      window.synchLeoCdpToGA4(vid);
    }
    if (typeof window.startLeoChatBot === "function") {
      window.startLeoChatBot(vid);
    }
  });
}