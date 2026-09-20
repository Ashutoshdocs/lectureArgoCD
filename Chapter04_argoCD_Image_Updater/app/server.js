const express = require("express");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 3000;

// Version is baked into the image at build time (see Dockerfile ARG APP_VERSION).
// When ArgoCD Image Updater bumps the tag, this value changes on screen.
const VERSION = process.env.APP_VERSION || "0.0.0-dev";

// A different accent colour per major.minor makes upgrades visually obvious.
function colorFor(version) {
  const palette = ["#2563eb", "#059669", "#d97706", "#db2777", "#7c3aed", "#0891b2"];
  const n = version.split(".").slice(0, 2).join("");
  let sum = 0;
  for (const ch of n) sum += ch.charCodeAt(0);
  return palette[sum % palette.length];
}

app.get("/healthz", (_req, res) => res.status(200).send("ok"));

app.get("/", (_req, res) => {
  const accent = colorFor(VERSION);
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Frontend v${VERSION}</title>
  <style>
    :root { color-scheme: light dark; }
    body {
      margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      background: #0b1120; color: #e2e8f0;
    }
    .card {
      text-align: center; padding: 3rem 3.5rem; border-radius: 20px;
      background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08);
      box-shadow: 0 20px 60px rgba(0,0,0,0.4);
    }
    .ver { font-size: 3rem; font-weight: 800; color: ${accent}; margin: 0.25rem 0 0.75rem; }
    h1 { margin: 0; font-size: 1.25rem; font-weight: 600; }
    p { margin: 0.2rem 0; color: #94a3b8; font-size: 0.9rem; }
    .dot { display:inline-block; width:10px; height:10px; border-radius:50%; background:${accent}; margin-right:6px; }
  </style>
</head>
<body>
  <div class="card">
    <h1><span class="dot"></span>ArgoCD Image Updater Demo</h1>
    <div class="ver">v${VERSION}</div>
    <p>Served by pod: <strong>${os.hostname()}</strong></p>
    <p>Push a new image tag to ACR &rarr; Image Updater commits it to Git &rarr; ArgoCD syncs.</p>
  </div>
</body>
</html>`);
});

app.listen(PORT, () => console.log(`frontend v${VERSION} listening on :${PORT}`));
