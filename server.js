"use strict";

/**
 * STICKMAN CO-OP — локальный сервер.
 *
 * Делает две вещи на одном порту:
 *   1) отдаёт игру из ./public (HTML/JS/иконки);
 *   2) поднимает PeerJS signaling на /peerjs — через него игроки находят
 *      друг друга, а сами данные игры идут напрямую P2P (WebRTC).
 *
 * Запуск:  node server.js   (или ./start.sh / иконка на рабочем столе)
 * Порт:    PORT=9000 по умолчанию.
 */

const path = require("path");
const os = require("os");
const fs = require("fs");
const express = require("express");
const { ExpressPeerServer } = require("peer");

const PORT = Number(process.env.PORT || 9000);
const PUBLIC_DIR = path.join(__dirname, "public");

const app = express();
app.disable("x-powered-by");
app.set("trust proxy", true);

/** Собираем IPv4-адреса машины в локальной сети (без 127.0.0.1). */
function lanIPs() {
  const result = [];
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const info of ifaces[name] || []) {
      if (info.family === "IPv4" && !info.internal) result.push({ name, address: info.address });
    }
  }
  const rank = (ip) => {
    if (/^192\.168\./.test(ip)) return 0;
    if (/^10\./.test(ip)) return 1;
    if (/^172\.(1[6-9]|2\d|3[01])\./.test(ip)) return 2;
    return 3;
  };
  return result.sort((a, b) => rank(a.address) - rank(b.address)).map((x) => x.address);
}

/**
 * Публичная ссылка cloudflared (quick tunnel).
 * start.sh кладёт её в logs/tunnel.url, а PID — в tunnel.pid.
 * Отдаём URL, только если процесс туннеля жив.
 */
function readTunnelUrl() {
  try {
    const urlFile = path.join(__dirname, "logs", "tunnel.url");
    const pidFile = path.join(__dirname, "tunnel.pid");
    if (!fs.existsSync(urlFile) || !fs.existsSync(pidFile)) return null;
    const pid = parseInt(fs.readFileSync(pidFile, "utf8").trim(), 10);
    if (!pid) return null;
    try {
      process.kill(pid, 0);
    } catch (e) {
      return null;
    }
    const url = fs.readFileSync(urlFile, "utf8").trim();
    if (!/^https?:\/\/[^\s]+$/i.test(url)) return null;
    return url.replace(/\/$/, "") + "/";
  } catch (e) {
    return null;
  }
}

const server = app.listen(PORT, "0.0.0.0", () => {
  const ips = lanIPs();
  console.log("");
  console.log("  ╔══════════════════════════════════════════════╗");
  console.log("  ║          STICKMAN CO-OP  •  СЕРВЕР           ║");
  console.log("  ╚══════════════════════════════════════════════╝");
  console.log(`  Локально:  http://localhost:${PORT}/`);
  for (const ip of ips) console.log(`  В сети:    http://${ip}:${PORT}/`);
  console.log(`  Сигналинг: ws://<host>:${PORT}/peerjs`);
  console.log("  Остановка: ./stop.sh");
  console.log("");
});

server.on("error", (err) => {
  if (err && err.code === "EADDRINUSE") {
    console.error(`\n  Порт ${PORT} уже занят. Возможно, сервер уже запущен.\n`);
  } else {
    console.error("\n  Ошибка сервера:", err);
  }
  process.exit(1);
});

/* ---------- PeerJS signaling ---------- */
const peerServer = ExpressPeerServer(server, {
  path: "/",
  proxied: true,
  allow_discovery: false,
  debug: false,
  corsOptions: { origin: true },
});
app.use("/peerjs", peerServer);

let clients = 0;
peerServer.on("connection", (client) => {
  clients += 1;
  console.log(`[peer] + ${client && client.getId ? client.getId() : "?"}  (онлайн: ${clients})`);
});
peerServer.on("disconnect", (client) => {
  clients = Math.max(0, clients - 1);
  console.log(`[peer] - ${client && client.getId ? client.getId() : "?"}  (онлайн: ${clients})`);
});

/* ---------- Служебные эндпоинты ---------- */
app.get("/healthz", (req, res) => res.type("text/plain").send("ok"));

app.get("/api/status", (req, res) => {
  const ips = lanIPs();
  const primary = ips[0] || "127.0.0.1";
  const lanUrl = `http://${primary}:${PORT}/`;
  const tunnel = readTunnelUrl();
  const isLocalHost = /^(localhost|127\.0\.0\.1|\[?::1\]?)$/i.test(req.hostname);
  const requestUrl = `${req.protocol}://${req.get("host")}/`;
  // Если туннель активен — всегда даём публичную ссылку.
  // Иначе: с localhost — LAN-адрес, с другого хоста — тот, по которому пришли.
  const url = tunnel || (isLocalHost ? lanUrl : requestUrl);
  res.set("Cache-Control", "no-store");
  res.json({
    ok: true,
    port: PORT,
    ips,
    url,
    lanUrl,
    publicUrl: tunnel,
    localUrl: `http://localhost:${PORT}/`,
    clients,
    version: require("./package.json").version,
  });
});

/* ---------- Игра ---------- */
app.use(
  express.static(PUBLIC_DIR, {
    extensions: ["html"],
    setHeaders(res, filePath) {
      if (filePath.endsWith(".html")) res.setHeader("Cache-Control", "no-store");
    },
  })
);
app.get("/", (req, res) => res.sendFile(path.join(PUBLIC_DIR, "index.html")));

process.on("SIGINT", () => {
  console.log("\n  Сервер остановлен.");
  process.exit(0);
});
process.on("SIGTERM", () => {
  process.exit(0);
});
