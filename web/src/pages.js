// Link pages for meditations shared in Brownie's store, shared by the Vercel
// function (api/page.js) and the Cloudflare Worker (src/worker.js).
//
//   /m/<id>        a page with the script and a social card; opens the app when it's installed
//   /m/<id>.med    the raw script
//   /.well-known/apple-app-site-association   lets iOS hand /m/ links to the app
//
// Records come from the CloudKit public database through CloudKit Web Services,
// with a read-only API token (CK_API_TOKEN).

const APP_ID = "B7P78ULCXS.com.joeedelman.meditations";

/// env: { CK_CONTAINER, CK_ENVIRONMENT, CK_API_TOKEN }
export async function handle(pathname, origin, env) {
  if (pathname === "/.well-known/apple-app-site-association") {
    return Response.json({
      applinks: { details: [{ appIDs: [APP_ID], components: [{ "/": "/m/*.med", exclude: true }, { "/": "/m/*" }] }] },
    });
  }

  const match = pathname.match(/^\/m\/([A-Za-z0-9_-]+?)(\.med)?\/?$/);
  if (match) {
    const [, id, raw] = match;
    const item = await lookup(env, id);
    if (!item) return page(notFound(), 404);
    if (raw) {
      return new Response(item.body, {
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "content-disposition": `attachment; filename="${slug(item.title)}.med"`,
          "cache-control": "public, max-age=300",
        },
      });
    }
    return page(meditationPage(item, id, origin));
  }

  if (pathname === "/") return page(home(origin));
  return page(notFound(), 404);
}

async function lookup(env, id) {
  const endpoint =
    `https://api.apple-cloudkit.com/database/1/${env.CK_CONTAINER}/${env.CK_ENVIRONMENT}` +
    `/public/records/lookup?ckAPIToken=${encodeURIComponent(env.CK_API_TOKEN)}`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ records: [{ recordName: id }] }),
  });
  if (!response.ok) {
    console.log("CloudKit lookup failed", response.status, await response.text());
    return null;
  }
  const record = (await response.json()).records?.[0];
  if (!record || record.serverErrorCode || record.recordType !== "SharedMeditation") return null;
  const field = (name) => record.fields?.[name]?.value;
  return {
    title: field("title") || "Untitled",
    tags: field("tags") || [],
    body: field("body") || "",
    authorName: field("authorName") || "",
  };
}

function meditationPage(item, id, origin) {
  const pageURL = `${origin}/m/${id}`;
  const byline = item.authorName ? `by ${item.authorName}` : "";
  const tags = item.tags.map((t) => `#${t}`).join(" ");
  const description = [byline ? `A meditation ${byline}` : "A meditation", tags].filter(Boolean).join(" · ");
  return {
    title: item.title,
    head: `
    <meta name="description" content="${esc(description)}">
    <meta property="og:type" content="article">
    <meta property="og:site_name" content="Brownie">
    <meta property="og:title" content="${esc(item.title)}">
    <meta property="og:description" content="${esc(description)}">
    <meta property="og:url" content="${esc(pageURL)}">
    <meta property="og:image" content="${origin}/card.png">
    <meta property="og:image:width" content="1200">
    <meta property="og:image:height" content="630">
    <meta name="twitter:card" content="summary_large_image">`,
    body: `
    <header>
      <h1>${esc(item.title)}</h1>
      ${byline ? `<p class="byline">${esc(byline)}</p>` : ""}
      ${tags ? `<p class="tags">${esc(tags)}</p>` : ""}
    </header>
    <div class="actions">
      <a class="button primary" href="brownie://m/${esc(id)}">Open in Brownie</a>
      <a class="button" href="/m/${esc(id)}.med">Download .med</a>
    </div>
    <pre>${esc(item.body)}</pre>`,
  };
}

function home(origin) {
  return {
    title: "Brownie",
    head: `
    <meta property="og:title" content="Brownie">
    <meta property="og:description" content="Meditations, shared.">
    <meta property="og:image" content="${origin}/card.png">
    <meta name="twitter:card" content="summary_large_image">`,
    body: `<header><h1>Brownie</h1><p class="byline">Meditations people share from the Brownie app.</p></header>`,
  };
}

function notFound() {
  return {
    title: "Not found",
    head: "",
    body: `<header><h1>Not found</h1><p class="byline">This meditation is no longer in the store.</p></header>`,
  };
}

function page({ title, head, body }, status = 200) {
  const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${esc(title)} · Brownie</title>${head}
    <style>
      :root { --bg: #faf7f1; --text: #28201a; --muted: #786a5a; --panel: #f0e9dc; --accent: #c98a2b; }
      @media (prefers-color-scheme: dark) {
        :root { --bg: #1c1916; --text: #f3ece2; --muted: #a89a88; --panel: #2a2520; --accent: #e0a347; }
      }
      * { box-sizing: border-box; }
      body { margin: 0; background: var(--bg); color: var(--text);
             font: 17px/1.5 -apple-system, BlinkMacSystemFont, "Inter", sans-serif; }
      main { max-width: 640px; margin: 0 auto; padding: 40px 16px 64px; }
      h1 { font-size: 28px; line-height: 1.2; margin: 0 0 4px; }
      .byline, .tags { margin: 0; color: var(--muted); }
      .actions { display: flex; gap: 10px; flex-wrap: wrap; margin: 24px 0; }
      .button { padding: 10px 16px; border-radius: 12px; background: var(--panel);
                color: var(--text); text-decoration: none; font-weight: 600; }
      .button.primary { background: var(--accent); color: #fff; }
      pre { background: var(--panel); border-radius: 14px; padding: 16px; margin: 0;
            white-space: pre-wrap; word-wrap: break-word; font: 15px/1.5 ui-monospace, Menlo, monospace; }
    </style>
  </head>
  <body><main>${body}</main></body>
</html>`;
  return new Response(html, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=300" },
  });
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function slug(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "meditation";
}
