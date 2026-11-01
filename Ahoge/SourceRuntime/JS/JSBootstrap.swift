/// JavaScript evaluated before every source bundle. Form encoding lives here so it is the same
/// encodeURIComponent the Node runtime uses (Swift's percent-encoding sets differ).
enum JSBootstrap {
    static let source = """
    var CloudflareError = class CloudflareError extends Error {
      constructor(url) { super("Cloudflare challenge at " + url); this.name = "CloudflareError"; this.url = url; }
    };
    function __ahoge_encodeForm(object) {
      return Object.keys(object).map(function (k) {
        return encodeURIComponent(k) + "=" + encodeURIComponent(String(object[k]));
      }).join("&");
    }
    var http = (function (native) {
      function hasHeader(headers, name) {
        return Object.keys(headers).some(function (k) { return k.toLowerCase() === name; });
      }
      function request(method, url, options) {
        options = options || {};
        var headers = {};
        var given = options.headers || {};
        Object.keys(given).forEach(function (k) { headers[k] = String(given[k]); });
        var body = options.body;
        var text = null;
        if (body !== undefined && body !== null) {
          if (typeof body === "object") {
            text = __ahoge_encodeForm(body);
            if (!hasHeader(headers, "content-type")) headers["Content-Type"] = "application/x-www-form-urlencoded";
          } else {
            text = String(body);
          }
        }
        return native(method, String(url), headers, text);
      }
      return {
        get: function (url, options) { return request("GET", url, options); },
        post: function (url, options) { return request("POST", url, options); }
      };
    })(__ahoge_http);
    var html = { parse: function (body, baseUrl) { return __ahoge_parse(String(body), String(baseUrl)); } };
    var console = { log: function () { __ahoge_log(Array.prototype.map.call(arguments, String).join(" ")); } };
    """
}
