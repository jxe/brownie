// Cloudflare Worker entry for the link pages (needs nxhx.org's DNS on Cloudflare).
import { handle } from "./pages.js";

export default {
  fetch(request, env) {
    const url = new URL(request.url);
    return handle(url.pathname, url.origin, env);
  },
};
