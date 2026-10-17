// Safari runs this in the shared page before the Share Extension opens (NSExtensionJavaScriptPreprocessingFile),
// so the extension receives the rendered DOM: pages that build their recipe with JavaScript arrive complete.
var GetPageSource = function() {};

GetPageSource.prototype = {
    run: function(parameters) {
        parameters.completionFunction({
            "html": document.documentElement.outerHTML,
            "title": document.title,
            "url": document.location.href
        });
    },

    finalize: function(parameters) {}
};

var ExtensionPreprocessingJS = new GetPageSource;
