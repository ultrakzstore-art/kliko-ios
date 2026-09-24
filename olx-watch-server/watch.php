<?php
// Ловля новых объявлений: поиск по ссылкам и турбо по номерам. Вызывается из cron.php.

declare(strict_types=1);
require_once __DIR__ . '/lib.php';

const FRESH_SEC = 3600;     // «Топ»-объявления бывают старыми: такие не новые
const MISS_GIVE_UP = 12;    // номер пустой 12 проверок подряд — пропускаем

// Бережём себя от блокировки: 403/429 → пауза, каждый раз вдвое дольше, до 15 минут.
function blocked(): bool {
    return time() < (int)kv_get('backoff_until', 0);
}

function handle_olx_error(Throwable $e): bool {
    if ($e instanceof OlxHttpError && in_array($e->status, [403, 429], true)) {
        $ms = min(900, max(60, (int)kv_get('backoff_sec', 0) * 2));
        kv_set('backoff_sec', $ms);
        kv_set('backoff_until', time() + $ms);
        kv_set('last_block', ['at' => time(), 'status' => $e->status]);
        return true;
    }
    return false;
}

function request_ok(): void {
    if (kv_get('backoff_sec', 0)) kv_set('backoff_sec', 0);
}

function bump_frontier(int $id): void {
    if ($id > (int)kv_get('frontier', 0)) kv_set('frontier', $id);
}

function stat_add(string $k, int $n = 1): void {
    $s = kv_get('stats', []);
    $s[$k] = ($s[$k] ?? 0) + $n;
    kv_set('stats', $s);
}

// ---------- поиск ----------

function poll_due_subs(int $pollSec): void {
    foreach (subs_all() as $sub) {
        if ($sub['paused'] || time() - (int)$sub['last_poll'] < $pollSec || blocked()) continue;
        poll_sub($sub);
    }
}

function poll_sub(array $sub): void {
    try {
        $res = fetch_search($sub['url']);
        request_ok();
        stat_add('search_ok');
    } catch (Throwable $e) {
        stat_add('search_err');
        handle_olx_error($e);
        sub_update((int)$sub['id'], ['last_poll' => time(), 'last_error' => $e->getMessage()]);
        return;
    }
    $ads = $res['ads'];
    foreach ($ads as $a) bump_frontier($a['id']);
    $patch = [
        'last_poll' => time(),
        'last_error' => $ads ? '' : 'поиск ничего не вернул',
        'learned' => learn($sub['learned'], array_filter($ads, fn($a) => !$a['promoted'])),
    ];
    // Первый проход — только запоминаем выдачу, чтобы не засыпать старьём.
    if (!$sub['initialized']) {
        foreach ($ads as $a) ad_remember($a['id']);
        sub_update((int)$sub['id'], $patch + ['initialized' => 1]);
        return;
    }
    sub_update((int)$sub['id'], $patch);
    $sent = (int)$sub['sent'];
    foreach ($ads as $a) {
        if (ad_seen($a['id'])) continue;
        ad_remember($a['id']);
        if ($a['created_at'] && time() - $a['created_at'] > FRESH_SEC) continue;
        $full = enrich($a);
        ad_store($full, 'search', [(int)$sub['id']]);
        push_ad($full, [$sub], 'search');
        sub_update((int)$sub['id'], ['sent' => ++$sent]);
    }
}

// Подробности — из карточки; не вышло — оставляем то, что дал поиск.
function enrich(array $ad): array {
    try {
        $full = fetch_offer($ad['id']);
        if (!$full) return $ad;
        foreach ($full as $k => $v) if ($v !== '' && $v !== null && $v !== []) $ad[$k] = $v;
    } catch (Throwable $e) {
    }
    return $ad;
}

// ---------- турбо ----------

function turbo_tick(int $window): void {
    if (!kv_get('turbo', true) || blocked()) return;
    $frontier = (int)kv_get('frontier', 0);
    $subs = array_values(array_filter(subs_all(), fn($s) => !$s['paused'] && $s['initialized']));
    if (!$frontier || !$subs) return;
    $misses = kv_get('misses', []);
    $ids = [];
    for ($id = $frontier + 1; count($ids) < $window && $id <= $frontier + $window * 5; $id++) {
        if (($misses[$id] ?? 0) < MISS_GIVE_UP && !ad_seen($id)) $ids[] = $id;
    }
    foreach ($ids as $id) {
        if (blocked()) break;
        try {
            $offer = fetch_offer($id);
            request_ok();
            stat_add('turbo_probes');
        } catch (Throwable $e) {
            if (handle_olx_error($e)) break;
            continue;
        }
        if (!$offer) { $misses[$id] = ($misses[$id] ?? 0) + 1; continue; }
        unset($misses[$id]);
        bump_frontier($id);
        stat_add('turbo_found');
        kv_set('last_turbo_hit', time());
        if (!ad_remember($id)) continue;
        $hit = array_values(array_filter($subs, fn($s) => sub_matches($s, $offer)));
        if (!$hit) continue;
        ad_store($offer, 'turbo', array_map(fn($s) => (int)$s['id'], $hit));
        push_ad($offer, $hit, 'turbo');
        foreach ($hit as $s) sub_update((int)$s['id'], ['sent' => (int)$s['sent'] + 1]);
    }
    $frontier = (int)kv_get('frontier', 0);
    $misses = array_filter($misses, fn($n, $id) => $id > $frontier - 500, ARRAY_FILTER_USE_BOTH);
    kv_set('misses', $misses);
}
