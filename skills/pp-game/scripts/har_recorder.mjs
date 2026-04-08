#!/usr/bin/env node
/**
 * PP Live Casino HAR 录制服务（交互式）
 *
 * 职责：
 *   1. 开浏览器 + 捕获 HTTP/WS 流量
 *   2. 实时解析游戏 WS 消息，向 stdout 汇报关键事件
 *   3. 到时间/Ctrl+C 后合并输出 HAR（含 _webSocketMessages）
 *
 * UI 操作由 Claude 通过 agent-browser --cdp <cdp-port> 完成。
 *
 * 用法:
 *   node <this-script> <游戏URL> [--duration=10m] [--output=game.har] [--cdp-port=9222]
 *
 * 汇报格式（每行一个 JSON）:
 *   {"event":"ready",  "cdpPort":9222, "gameType":"megaroulette", "tableId":"xxx"}
 *   {"event":"ws_open", "url":"wss://..."}
 *   {"event":"game_loaded", "initSeq":["table","dealer","game",...]}
 *   {"event":"bets_open",  "gameId":"139...", "round":3}
 *   {"event":"bets_closed","gameId":"139..."}
 *   {"event":"game_result","gameId":"139...","score":"22","color":"black","round":3}
 *   {"event":"bet_confirmed","betCode":"47","amount":"0.1","description":"Even"}
 *   {"event":"win","gameId":"...","win":"0.20"}
 *   {"event":"status", "elapsed":30, "remaining":90, "wsMessages":1500, "rounds":3}
 *   {"event":"saved", "path":"docs/hars/...", "rounds":5, "wsMessages":4000}
 */

import { createRequire } from 'module';
import { writeFileSync, readFileSync, unlinkSync, mkdirSync } from 'fs';
import { resolve, dirname } from 'path';
import { execSync } from 'child_process';

// 自适应找 playwright：项目本地 → 全局 node_modules
let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch {
  // ESM 下全局包不可见，用 createRequire 找
  const globalPrefix = execSync('npm root -g', { encoding: 'utf-8' }).trim();
  const require = createRequire(globalPrefix + '/');
  ({ chromium } = require('playwright'));
}

// ─── 参数解析 ────────────────────────────────────────────
const rawArgs = process.argv.slice(2);
const gameUrl = rawArgs.find(a => a.startsWith('http'));
if (!gameUrl) {
  console.error('用法: node scripts/har_recorder.mjs <游戏URL> [--duration=10m] [--output=game.har] [--cdp-port=9222]');
  process.exit(1);
}

function parseDuration(str) {
  const m = str.match(/^(\d+)(s|m|h)$/);
  if (!m) return parseInt(str) * 1000;
  const val = parseInt(m[1]);
  if (m[2] === 's') return val * 1000;
  if (m[2] === 'm') return val * 60 * 1000;
  return val * 3600 * 1000;
}

const durationStr = rawArgs.find(a => a.startsWith('--duration='))?.split('=')[1] || '10m';
const durationMs = parseDuration(durationStr);
const cdpPort = parseInt(rawArgs.find(a => a.startsWith('--cdp-port='))?.split('=')[1] || '9222');

const urlParams = new URL(gameUrl).searchParams;
const tableId = urlParams.get('table_id') || 'unknown';
const gameType = urlParams.get('gametype') || 'unknown';
const outputArg = rawArgs.find(a => a.startsWith('--output='))?.split('=')[1];
const outputPath = resolve(outputArg || `docs/hars/${gameType}/${tableId}.har`);

// ─── 事件汇报 ────────────────────────────────────────────
function emit(event, data = {}) {
  console.log(JSON.stringify({ event, ...data }));
}

// ─── 状态 ────────────────────────────────────────────────
const wsConnections = [];
let gameResultCount = 0;
let wsMsgCount = 0;
let initSeq = [];
let initDone = false;
let currentGameId = null;

function onWsMessage(wsUrl, direction, data) {
  const conn = wsConnections.find(c => c.url === wsUrl);
  if (!conn) return;

  conn.messages.push({
    type: direction,
    time: Date.now() / 1000,
    opcode: 1,
    data: typeof data === 'string' ? data : data.toString(),
  });
  wsMsgCount++;

  // 只解析游戏 WS（含 /game 的连接）
  if (!wsUrl.includes('/game')) return;
  if (direction !== 'receive' || typeof data !== 'string') return;

  // 提取 XML 标签名
  const tagMatch = data.match(/^<(\w+)/);
  if (!tagMatch) return;
  const tag = tagMatch[1];

  // 初始化序列
  if (!initDone) {
    initSeq.push(tag);
    if (tag === 'subscribe') {
      initDone = true;
      emit('game_loaded', { initSeq });
    }
  }

  // 游戏事件
  switch (tag) {
    case 'betsopen': {
      const gid = data.match(/game="(\d+)"/)?.[1];
      if (gid) currentGameId = gid;
      gameResultCount++;
      emit('bets_open', { gameId: gid, round: gameResultCount });
      break;
    }
    case 'betsclosingsoon': {
      const gid = data.match(/game="(\d+)"/)?.[1];
      emit('bets_closing_soon', { gameId: gid });
      break;
    }
    case 'betsclosed': {
      const gid = data.match(/game="(\d+)"/)?.[1];
      emit('bets_closed', { gameId: gid });
      break;
    }
    case 'gameresult': {
      // 跳过 <sc> 内嵌的历史 gameresult
      if (data.includes('<sc')) break;
      const score = data.match(/score="(\w+)"/)?.[1];
      const color = data.match(/color="(\w+)"/)?.[1];
      const gid = data.match(/id="(\d+)"/)?.[1];
      const megaWin = data.match(/megaWin="(\w+)"/)?.[1];
      emit('game_result', { gameId: gid, score, color, megaWin, round: gameResultCount });
      break;
    }
    case 'bets': {
      // 服务器确认的投注
      const bets = [...data.matchAll(/betCode="(\d+)".*?amount="([\d.]+)".*?description="([^"]+)"/g)];
      for (const [, code, amount, desc] of bets) {
        emit('bet_confirmed', { betCode: code, amount, description: desc });
      }
      break;
    }
    case 'win': {
      const gid = data.match(/gameId="(\d+)"/)?.[1];
      const win = data.match(/win="([\d.]+)"/)?.[1];
      emit('win', { gameId: gid, win });
      break;
    }
    case 'rng': {
      // Mega Roulette 乘数分配
      const slots = [...data.matchAll(/number="(\d+)"\s+multiplier="(\d+)"/g)];
      if (slots.length > 0) {
        emit('rng', { slots: slots.map(([, n, m]) => ({ number: n, multiplier: m })) });
      }
      break;
    }
  }

  // 客户端发送的投注
  if (direction === 'send' && typeof data === 'string' && data.includes('<lpbet')) {
    const gid = data.match(/gId="(\d+)"/)?.[1];
    const bets = [...data.matchAll(/amt="([\d.]+)"\s+bc="(\d+)"/g)];
    emit('bet_sent', { gameId: gid, bets: bets.map(([, amt, bc]) => ({ amount: amt, betCode: bc })) });
  }
}

// ─── 主流程 ──────────────────────────────────────────────
async function main() {
  const tmpHarPath = outputPath + '.tmp';
  mkdirSync(dirname(outputPath), { recursive: true });

  const browser = await chromium.launch({
    headless: false,
    args: ['--window-size=1440,900', `--remote-debugging-port=${cdpPort}`],
  });

  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    recordHar: { path: tmpHarPath, urlFilter: /.*/ },
  });

  const page = await context.newPage();

  // WS 监听（跳过视频流 ws1.*/RA* 连接，体积太大且无分析价值）
  page.on('websocket', ws => {
    const wsUrl = ws.url();
    const isVideoStream = /ws\d*\.pragmaticplaylive\.net\/\w{2,4}\d/.test(wsUrl);
    emit('ws_open', { url: wsUrl, skipped: isVideoStream });
    if (isVideoStream) return;

    const conn = { url: wsUrl, messages: [] };
    wsConnections.push(conn);
    ws.on('framereceived', f => onWsMessage(wsUrl, 'receive', f.payload));
    ws.on('framesent', f => onWsMessage(wsUrl, 'send', f.payload));
    ws.on('close', () => emit('ws_close', { url: wsUrl.slice(0, 80) }));
  });

  // 导航
  await page.goto(gameUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });

  emit('ready', { cdpPort, gameType, tableId, duration: durationStr, output: outputPath });

  // 倒计时
  const totalSec = Math.round(durationMs / 1000);
  const startTime = Date.now();

  // 优雅退出
  let stopped = false;
  const graceful = async () => {
    if (stopped) return;
    stopped = true;
    emit('saving', {});
    await save(context, browser, tmpHarPath);
  };
  process.on('SIGINT', graceful);
  process.on('SIGTERM', graceful);

  // 状态轮询
  await new Promise(r => {
    const timer = setInterval(() => {
      if (stopped) { clearInterval(timer); r(); return; }
      const elapsed = Math.round((Date.now() - startTime) / 1000);
      const remaining = totalSec - elapsed;
      if (remaining <= 0) {
        clearInterval(timer);
        r();
      } else if (elapsed % 15 === 0 && elapsed > 0) {
        emit('status', { elapsed, remaining, wsMessages: wsMsgCount, rounds: gameResultCount });
      }
    }, 1000);
  });

  if (!stopped) await graceful();
}

async function save(context, browser, tmpPath) {
  await context.close();
  await browser.close();

  const har = JSON.parse(readFileSync(tmpPath, 'utf-8'));
  if (har.log.pages?.length > 0) har.log.pages[0].title = gameUrl;

  for (const conn of wsConnections) {
    if (conn.messages.length === 0) continue;
    har.log.entries.push({
      startedDateTime: new Date(conn.messages[0].time * 1000).toISOString(),
      time: 0,
      request: {
        method: 'GET', url: conn.url, httpVersion: 'HTTP/1.1',
        headers: [{ name: 'Connection', value: 'Upgrade' }, { name: 'Upgrade', value: 'websocket' }],
        queryString: [], cookies: [], headersSize: -1, bodySize: 0,
      },
      response: {
        status: 101, statusText: 'Switching Protocols', httpVersion: 'HTTP/1.1',
        headers: [{ name: 'Connection', value: 'Upgrade' }, { name: 'Upgrade', value: 'websocket' }],
        cookies: [], content: { size: 0, mimeType: '' }, redirectURL: '', headersSize: -1, bodySize: 0,
      },
      cache: {},
      timings: { send: 0, wait: 0, receive: 0 },
      _resourceType: 'websocket',
      _webSocketMessages: conn.messages,
    });
  }

  mkdirSync(dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, JSON.stringify(har, null, 2));
  try { unlinkSync(tmpPath); } catch {}

  const totalWs = wsConnections.reduce((s, c) => s + c.messages.length, 0);
  emit('saved', { path: outputPath, rounds: gameResultCount, wsMessages: totalWs });
  process.exit(0);
}

main().catch(err => {
  emit('error', { message: err.message });
  process.exit(1);
});
