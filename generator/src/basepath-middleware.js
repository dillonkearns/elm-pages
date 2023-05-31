// this middleware is only active when (config.base !== '/')

export function baseMiddleware(base) {
  // Keep the named function. The name is visible in debug logs via `DEBUG=connect:dispatcher ...`
  return function viteBaseMiddleware(req, res, next) {
    // `req.url` only contains the path, since that is what gets passed in the HTTP request.
    // See https://nodejs.org/api/http.html#http_message_url
    const path = req.url;

    if (base === "/") {
      // The RegExp will check for the slash, so we remove it here.
      base = "";
    }
    // We want to detect the base at the beginning, hence the `^`,
    // but also allow calling the base without a trailing slash, hence the `$`.
    const baseRegExp = new RegExp(`^${base}(/|$)`);
    if (baseRegExp.test(path)) {
      // rewrite url to remove base. this ensures that other middleware does
      // not need to consider base being prepended or not
      req.url = path.replace(baseRegExp, "/");
      return next();
    }

    if (path === "/" || path === "/index.html") {
      // redirect root visit to based url
      res.writeHead(302, {
        Location: base,
      });
      res.end();
      return;
    } else if (req.headers.accept && req.headers.accept.includes("text/html")) {
      // non-based page visit
      res.statusCode = 404;
      const suggestionUrl = `${base}/${path.slice(1)}`;
      res.end(
        `The server is configured with a public base URL of ${base} - ` +
          `did you mean to visit ${suggestionUrl} instead?`
      );
      return;
    }

    next();
  };
}
