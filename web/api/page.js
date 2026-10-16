// Vercel entry for the link pages. vercel.json rewrites every page path here as ?path=.
import { handle } from "../src/pages.js";

export const config = { runtime: "edge" };

export default function handler(request) {
  const url = new URL(request.url);
  return handle(url.searchParams.get("path") || "/", url.origin, {
    CK_CONTAINER: process.env.CK_CONTAINER || "iCloud.com.joeedelman.meditations",
    CK_ENVIRONMENT: process.env.CK_ENVIRONMENT || "production",
    CK_API_TOKEN: process.env.CK_API_TOKEN,
  });
}
