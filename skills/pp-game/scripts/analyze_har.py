#!/usr/bin/env python3
"""PP 游戏 HAR 分析工具 — 提取游戏 WS 消息、HTTP API、关键参数"""
import json, re, sys, os
from collections import defaultdict

def load_har(path):
    with open(path) as f:
        return json.load(f)

def get_game_ws(har):
    """提取游戏 WS 连接（gs*.pragmaticplaylive.net/game 或 本地 /game）"""
    for entry in har['log']['entries']:
        url = entry['request']['url']
        if '/game' in url and '_webSocketMessages' in entry:
            if 'pragmaticplaylive' in url or '9689' in url:
                return entry['_webSocketMessages'], url
    return [], ''

def get_page_params(har):
    """从页面 URL 提取游戏参数"""
    params = {}
    for page in har['log']['pages']:
        title = page.get('title', '')
        from urllib.parse import urlparse, parse_qs
        try:
            parsed = urlparse(title)
            qs = parse_qs(parsed.query)
            for k in ['table_id', 'gametype', 'tableVariant', 'casino_id', 'operator_theme', 'userId']:
                if k in qs:
                    params[k] = qs[k][0]
        except:
            pass
    return params

def classify_messages(msgs):
    """分类所有 WS 消息"""
    recv_types = defaultdict(list)
    send_types = defaultdict(list)

    for i, msg in enumerate(msgs):
        data = msg.get('data', '')
        direction = msg['type']

        if direction == 'send':
            if '<ping' in data:
                send_types['ping'].append(i)
            elif '<command' in data:
                if '<lpbet' in data:
                    send_types['command/lpbet'].append(i)
                elif '<placeBet' in data:
                    send_types['command/placeBet'].append(i)
                elif '<placebets' in data:
                    send_types['command/placebets'].append(i)
                else:
                    send_types['command/other'].append(i)
            else:
                send_types['unknown'].append(i)
        else:
            if data.startswith('{'):
                try:
                    parsed = json.loads(data)
                    for key in parsed.keys():
                        recv_types[f'JSON:{key}'].append(i)
                except:
                    recv_types['JSON:parse_error'].append(i)
            elif data.startswith('<'):
                m = re.match(r'<(\w+)', data)
                if m:
                    recv_types[f'XML:{m.group(1)}'].append(i)
            else:
                recv_types['binary/other'].append(i)

    return recv_types, send_types

def detect_format(msgs):
    """检测消息格式（JSON/XML）"""
    for msg in msgs:
        if msg['type'] == 'receive':
            data = msg.get('data', '')
            if data.startswith('{'):
                return 'JSON'
            elif data.startswith('<'):
                return 'XML'
    return 'UNKNOWN'

def extract_init_sequence(msgs):
    """提取初始化消息序列（前 N 条 receive）"""
    init = []
    for msg in msgs:
        if msg['type'] != 'receive':
            continue
        data = msg.get('data', '')
        tag = re.match(r'<(\w+)', data)
        if tag:
            t = tag.group(1)
        elif data.startswith('{'):
            try:
                t = 'JSON:' + list(json.loads(data).keys())[0]
            except:
                t = 'JSON:?'
        else:
            t = '?'
        init.append(t)
        if t == 'subscribe':
            break
    return init

def find_bet_round(msgs):
    """找到有用户下注的轮次，返回完整消息序列"""
    bet_indices = [i for i, m in enumerate(msgs) if m['type'] == 'send' and '<lpbet' in m.get('data', '')]
    if not bet_indices:
        return None, []

    bid = bet_indices[0]
    # 找该轮的 game 消息（往前找）
    game_id = None
    m = re.search(r'gId="(\d+)"', msgs[bid]['data'])
    if m:
        game_id = m.group(1)

    if not game_id:
        return None, []

    # 收集该 gameId 相关的所有消息
    round_msgs = []
    for i, msg in enumerate(msgs):
        data = msg.get('data', '')
        if game_id in data or (bid - 5 <= i <= bid + 30):
            d = 'RECV' if msg['type'] == 'receive' else 'SEND'
            tag = re.match(r'<(\w+)', data)
            tag_name = tag.group(1) if tag else ('JSON' if data.startswith('{') else '?')
            round_msgs.append((i, d, tag_name, data[:300]))

    return game_id, round_msgs

def extract_gameresult_payouts(msgs):
    """从 gameresult 提取 bXX=pYY 赔率数据"""
    results = []
    for msg in msgs:
        data = msg.get('data', '')
        if msg['type'] == 'receive' and '<gameresult' in data and '<sc' not in data:
            score = re.search(r'score="(\d+)"', data)
            color = re.search(r'color="(\w+)"', data)
            bets = re.findall(r'b(\d+)="p([\d.]+)"', data)
            mega = re.search(r'megaWin="(\w+)"', data)
            resMul = re.search(r'resultMultiplier="([\d.]+)"', data)
            results.append({
                'score': score.group(1) if score else '?',
                'color': color.group(1) if color else '?',
                'megaWin': mega.group(1) if mega else '?',
                'resultMultiplier': resMul.group(1) if resMul else None,
                'payouts': {int(bc): float(p) for bc, p in bets},
                'payout_count': len(bets),
            })
    return results

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_har.py <har_file> [--full]")
        sys.exit(1)

    har_path = sys.argv[1]
    full_mode = '--full' in sys.argv
    har = load_har(har_path)

    # 1. 页面参数
    params = get_page_params(har)
    print("=" * 70)
    print("游戏基本信息")
    print("=" * 70)
    for k, v in params.items():
        print(f"  {k}: {v}")

    # 2. WS 连接
    msgs, ws_url = get_game_ws(har)
    if not msgs:
        print("\n!! 未找到游戏 WS 连接")
        sys.exit(1)

    print(f"\n游戏 WS: {ws_url[:100]}")
    print(f"消息总数: {len(msgs)}")

    # 3. 消息格式
    fmt = detect_format(msgs)
    print(f"消息格式: {fmt}")

    # 4. 初始化序列
    init_seq = extract_init_sequence(msgs)
    print(f"\n初始化序列: {' → '.join(init_seq)}")

    # 5. 消息类型汇总
    recv_types, send_types = classify_messages(msgs)
    print(f"\n{'=' * 70}")
    print(f"上游消息类型 ({len(recv_types)} 种)")
    print(f"{'=' * 70}")
    for key in sorted(recv_types.keys()):
        indices = recv_types[key]
        sample = msgs[indices[0]]['data'][:150]
        print(f"  {key:35s} x{len(indices):>3}  [{indices[0]}] {sample}")

    print(f"\n下游消息类型 ({len(send_types)} 种)")
    for key in sorted(send_types.keys()):
        indices = send_types[key]
        sample = msgs[indices[0]]['data'][:150]
        print(f"  {key:35s} x{len(indices):>3}  {sample}")

    # 6. 用户下注轮次
    game_id, round_msgs = find_bet_round(msgs)
    if game_id:
        print(f"\n{'=' * 70}")
        print(f"用户下注轮次 (gameId={game_id})")
        print(f"{'=' * 70}")
        for idx, d, tag, data in round_msgs:
            print(f"  [{idx:>3}] {d:4s} <{tag:25s}> {data[:200]}")

    # 7. gameresult 赔率分析
    results = extract_gameresult_payouts(msgs)
    if results and results[0]['payout_count'] > 0:
        print(f"\n{'=' * 70}")
        print(f"gameresult 赔率分析 ({len(results)} 轮)")
        print(f"{'=' * 70}")
        for r in results[:3]:
            print(f"  score={r['score']} {r['color']} megaWin={r['megaWin']} resMul={r['resultMultiplier']} payouts={r['payout_count']}个")
            for bc, p in sorted(r['payouts'].items())[:5]:
                print(f"    b{bc} = p{p}")
            if r['payout_count'] > 5:
                print(f"    ... 共 {r['payout_count']} 个")

    # 8. 完整时序（--full 模式）
    if full_mode:
        print(f"\n{'=' * 70}")
        print(f"完整消息时序")
        print(f"{'=' * 70}")
        for i, msg in enumerate(msgs):
            data = msg.get('data', '')
            d = 'RECV' if msg['type'] == 'receive' else 'SEND'
            tag = re.match(r'<(\w+)', data)
            tag_name = tag.group(1) if tag else ('JSON' if data.startswith('{') else '?')
            print(f"  [{i:>3}] {d:4s} <{tag_name:25s}> {data[:150]}")

if __name__ == '__main__':
    main()
