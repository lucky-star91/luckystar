// ★ 카카오톡 직원 알림 서버 함수
// action: status · exchange(카카오 로그인 코드 → 토큰) · friends(친구 목록) · test(지금 발송) · daily(매일 9시, pg_cron 이 호출)
// 비밀값(Edge Function Secrets): KAKAO_CLIENT_SECRET  ·  SUPABASE_URL / SERVICE_ROLE_KEY / ANON_KEY 는 자동 제공
// 매일 발송 확인값은 DB app_private key='kakao_cron' (supabase/kakao_notify.sql 의 예약 설정 참고)
// 할 일 계산은 index.html 의 todoLists·estStageInfo 와 같은 규칙 — 그쪽을 바꾸면 여기도 같이 바꿀 것
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const KAKAO_REST_KEY = "2dc628e1327819fb2a62692f92f8112e"; // 공개돼도 되는 키
const SITE = "https://project-hv4qh.vercel.app";
const ADMIN_EMAIL = "kyuill75@gmail.com";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(SB_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "Content-Type": "application/json" } });

// ── 요청한 사람이 직원인지 (구글 로그인 + is_staff) ──
async function staffUser(req: Request) {
  const auth = req.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return null;
  const c = createClient(SB_URL, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const { data: u } = await c.auth.getUser();
  if (!u?.user) return null;
  const { data: ok } = await c.rpc("is_staff");
  return ok ? u.user : null;
}

// ── 카카오 API ──
async function kauth(params: Record<string, string>) {
  const body = new URLSearchParams({ client_id: KAKAO_REST_KEY, client_secret: Deno.env.get("KAKAO_CLIENT_SECRET") || "", ...params });
  const r = await fetch("https://kauth.kakao.com/oauth/token", { method: "POST", body });
  const d = await r.json();
  if (!r.ok) throw new Error("카카오 토큰 오류: " + (d.error_description || d.error || r.status));
  return d;
}
async function kapi(path: string, token: string, form?: Record<string, string>) {
  const r = await fetch("https://kapi.kakao.com" + path, {
    method: form ? "POST" : "GET",
    headers: { Authorization: "Bearer " + token },
    body: form ? new URLSearchParams(form) : undefined,
  });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error("카카오 API 오류(" + path + "): " + (d.msg || d.code || r.status));
  return d;
}
// 매일 9시 예약(pg_cron)이 보내는 비밀값 — app_private 표(화면에서 못 읽음)에 있음
async function cronSecret() {
  const { data } = await admin.from("app_private").select("value").eq("key", "kakao_cron").maybeSingle();
  return (data?.value as string) || "";
}
const later = (sec: number) => new Date(Date.now() + sec * 1000).toISOString();

// 보내는 계정 토큰 (만료 1분 전이면 갱신)
async function senderToken() {
  const { data: s } = await admin.from("kakao_sender").select("*").eq("id", 1).maybeSingle();
  if (!s?.refresh_token) throw new Error("보내는 카카오 계정이 연결되지 않았습니다. 환경설정에서 연결해 주세요.");
  if (s.access_token && new Date(s.expires_at).getTime() > Date.now() + 60000) return s.access_token as string;
  const t = await kauth({ grant_type: "refresh_token", refresh_token: s.refresh_token });
  const upd: Record<string, unknown> = { access_token: t.access_token, expires_at: later(t.expires_in), updated_at: new Date().toISOString() };
  if (t.refresh_token) { upd.refresh_token = t.refresh_token; upd.refresh_expires_at = later(t.refresh_token_expires_in); }
  await admin.from("kakao_sender").update(upd).eq("id", 1);
  return t.access_token as string;
}

// ── 할 일 계산 (index.html 과 같은 규칙, 날짜는 한국 시간 기준) ──
const parseJSON = (v: unknown, d: any) => { try { return typeof v === "string" ? JSON.parse(v || JSON.stringify(d)) : (v || d); } catch { return d; } };
// 화면에서 저장한 'YYYY-MM-DDTHH:MM' (시간대 없음) 은 한국 시간으로 읽음
const tOf = (v: unknown) => {
  let s = String(v || "").trim(); if (!s) return NaN;
  if (/^\d{4}-\d\d-\d\d$/.test(s)) s += "T00:00";
  if (s.includes("T") && !/([zZ]|[+-]\d\d:?\d\d)$/.test(s)) s += "+09:00";
  return new Date(s).getTime();
};
const KST = 9 * 3600000;
const dayKey = (t: number) => new Date(t + KST).toISOString().slice(0, 10);
const hm = (t: number) => new Date(t + KST).toISOString().slice(11, 16);
const md = (t: number) => { const d = new Date(t + KST); return (d.getUTCMonth() + 1) + "/" + d.getUTCDate(); };
const WEEK = ["일", "월", "화", "수", "목", "금", "토"];
const fmt = (n: number) => Math.round(Number(n) || 0).toLocaleString("ko-KR");
const normStatusObj = (o: any) => {
  const r = { ...(o || {}) }; if ("견적예정" in r) { if (!("본견적발송" in r)) r["본견적발송"] = r["견적예정"]; delete r["견적예정"]; }
  // 예전 '설치 예정' 날짜는 설치·공사 일정(제작시작~제작완료)으로 읽음 (status_checked 의 설치함은 그대로)
  if (typeof r["설치완료"] === "string") { if (!r["제작시작"] && r["설치완료"]) { const d = new Date(tOf(r["설치완료"]) + KST).toISOString().slice(0, 10); r["제작시작"] = d; r["제작완료"] = d; } delete r["설치완료"]; }
  return r;
};
const getStage = (sd: any, sc: any, deposit: unknown, balancePaid: unknown) => {
  if (sc["설치완료"]) return balancePaid ? "완료" : "설치완료";
  if ((Number(deposit) || 0) > 0 || sd["제작중"]) return "제작중";
  if (sd["본견적발송"]) return "본견적발송";
  if (sd["방문상담 및 실측"]) return "방문상담 및 실측";
  if (sd["가견적발송"]) return "가견적발송";
  return "작성중";
};
const lastSentAt = (sd: any) => Math.max(...["가견적발송", "본견적발송"].map((k) => sd[k] ? tOf(sd[k]) : 0).filter((t) => !isNaN(t)), 0);
const prodDays = (sd: any) => { const a = Date.parse(String(sd["제작시작"] || "").slice(0, 10)), b = Date.parse(String(sd["제작완료"] || "").slice(0, 10)); return isNaN(a) || isNaN(b) ? 0 : Math.max(1, Math.round((b - a) / 86400000) + 1); };
function info(e: any, holdDays: number, delayDays: number) {
  const sd = normStatusObj(parseJSON(e.status_dates, {}));
  let sc = normStatusObj(parseJSON(e.status_checked, {}));
  if (sd["본견적발송"] && !sc["방문상담 및 실측"]) sc = { ...sc, "방문상담 및 실측": true };
  const meta = parseJSON(e.meta, {});
  const stage = getStage(sd, sc, e.deposit_amount, e.balance_paid);
  const lost = !!meta.lost, deleted = !!meta.deletedAt;
  const hold = !lost && (stage === "가견적발송" || stage === "본견적발송") && holdDays > 0 && lastSentAt(sd) > 0 && Date.now() - lastSentAt(sd) > holdDays * 86400000;
  const vt = tOf(sd["방문상담 및 실측"]);
  const delayed = !lost && delayDays > 0 && stage === "방문상담 및 실측" && !!sc["방문상담 및 실측"] && !sd["본견적발송"] && !isNaN(vt) && Date.now() - vt > delayDays * 86400000;
  return { sd, sc, stage, hold, lost, deleted, delayed };
}
const short = (s: string, n = 14) => { s = String(s || "고객").trim(); return s.length > n ? s.slice(0, n) + "…" : s; };
const estUrl = (id: string) => `${SITE}/#/est-edit/${id}`;
const SCHED_URL = `${SITE}/#/sched-biweek`;

// 할 일 한 줄: title(종류·시간) · desc(고객명 등) · id(누르면 열 견적)
type Item = { t: number; title: string; desc: string; id: string };
type Section = { title: string; items: Item[] };

async function buildDigest(): Promise<Section[]> {
  const { data: stRow } = await admin.from("app_settings").select("value").eq("key", "estimate").maybeSingle();
  const st = parseJSON(stRow?.value, {});
  const holdDays = Number(st.holdDays ?? 30) || 0, delayDays = Number(st.delayDays ?? 0) || 0;
  const { data: ests, error } = await admin.from("estimates").select("*");
  if (error) throw new Error("견적 읽기 오류: " + error.message);
  const now = Date.now(), today = dayKey(now), weekEnd = dayKey(now + 7 * 86400000);
  const todayL: Item[] = [], weekL: Item[] = [], unpaid: Item[] = [];
  const sched = (e: any, kind: string, t: number, detail = "") => {
    if (isNaN(t)) return; const k = dayKey(t);
    const desc = short(e.client_name) + (detail ? " · " + detail : "");
    if (k === today) todayL.push({ t, title: `${kind} ${hm(t)}`, desc, id: e.id });
    else if (k > today && k <= weekEnd) weekL.push({ t, title: `${md(t)}(${WEEK[new Date(t + KST).getUTCDay()]}) ${kind}`, desc, id: e.id });
  };
  for (const e of ests || []) {
    const i = info(e, holdDays, delayDays); if (i.lost || i.deleted) continue;
    if (i.sd["방문상담 및 실측"] && !i.sc["방문상담 및 실측"]) sched(e, "🏠 방문", tOf(i.sd["방문상담 및 실측"]));
    if (i.sd["제작시작"] && !i.sc["설치완료"]) {
      const s0 = tOf(String(i.sd["제작시작"]).slice(0, 10) + "T09:00"), days = prodDays(i.sd) || 1;
      for (let k = 0; k < days; k++) sched(e, days > 1 ? "🔨 설치·공사" : "🎉 설치", s0 + k * 86400000, days > 1 ? `${k + 1}/${days}일` : "");
    }
    for (const v of parseJSON(e.extra_visits, []) as any[]) if (v.at && !v.done) sched(e, "🔧 " + (v.type || "방문"), tOf(v.at), v.reason || "");
    if (i.delayed) weekL.push({ t: Infinity, title: "⚠ 본견적 지연", desc: short(e.client_name), id: e.id });
    if (!i.hold && (i.stage === "가견적발송" || i.stage === "본견적발송") && holdDays > 0) {
      const left = Math.ceil((lastSentAt(i.sd) + holdDays * 86400000 - now) / 86400000);
      if (left >= 0 && left <= 5) weekL.push({ t: Infinity, title: `⏳ 보류까지 ${left}일`, desc: short(e.client_name) + " · 연락 필요", id: e.id });
    }
    if (i.stage === "설치완료") unpaid.push({ t: 0, title: "💰 " + short(e.client_name), desc: fmt(Math.max(0, (Number(e.total_amount) || 0) - (Number(e.deposit_amount) || 0) - (Number(e.mid_amount) || 0))) + "원", id: e.id });
  }
  todayL.sort((a, b) => a.t - b.t); weekL.sort((a, b) => a.t - b.t);
  const d = new Date(now + KST), day = `${d.getUTCMonth() + 1}/${d.getUTCDate()}(${WEEK[d.getUTCDay()]})`;
  return [
    { title: `📌 ${day} 오늘 할 일 ${todayL.length}건`, items: todayL },
    { title: `📅 1주일 할 일 ${weekL.length}건`, items: weekL },
    { title: `💰 잔금 미입금 ${unpaid.length}건`, items: unpaid },
  ];
}

// 카카오 메시지 양식: 2건 이상 → 목록형(항목마다 견적 링크, 최대 3개 + '외 N건' 버튼), 1건 → 글자형(견적 링크 버튼), 0건 → 안 보냄
const lnk = (u: string) => ({ web_url: u, mobile_web_url: u });
function templates(secs: Section[]) {
  const out: { tpl: string; preview: string }[] = [];
  for (const s of secs) {
    if (!s.items.length) continue;
    const shown = s.items.slice(0, 3), more = s.items.length - shown.length;
    const preview = [s.title, ...shown.map((x) => `· ${x.title} ${x.desc}  → 견적서`), more ? `[외 ${more}건 더 보기]` : shown.length >= 2 ? "[일정표 열기]" : "[견적서 열기]"].join("\n");
    if (shown.length >= 2) {
      out.push({ preview, tpl: JSON.stringify({
        object_type: "list", header_title: s.title, header_link: lnk(SCHED_URL),
        contents: shown.map((x) => ({ title: x.title, description: x.desc, link: lnk(estUrl(x.id)) })),
        buttons: [{ title: more ? `외 ${more}건 더 보기` : "일정표 열기", link: lnk(SCHED_URL) }],
      }) });
    } else {
      const x = shown[0];
      out.push({ preview, tpl: JSON.stringify({ object_type: "text", text: `${s.title}\n${x.title}\n${x.desc}`, link: lnk(estUrl(x.id)), button_title: "견적서 열기" }) });
    }
  }
  if (!out.length) {
    const text = secs[0].title.replace(/ 오늘 할 일 0건$/, "") + " 오늘·1주일 할 일과 잔금 미입금이 없습니다.";
    out.push({ preview: text, tpl: JSON.stringify({ object_type: "text", text, link: lnk(SCHED_URL), button_title: "일정표 열기" }) });
  }
  return out;
}

async function sendDigest() {
  const { data: cfgRow } = await admin.from("app_settings").select("value").eq("key", "kakao_notify").maybeSingle();
  const cfg = parseJSON(cfgRow?.value, {});
  const uuids: string[] = (cfg.recipients || []).map((r: any) => r.uuid).filter(Boolean);
  if (!uuids.length && !cfg.sendToMe) throw new Error("받는 사람이 없습니다. 환경설정에서 직원을 선택해 주세요.");
  const token = await senderToken();
  const msgs = templates(await buildDigest());
  const fails: string[] = [];
  for (const m of msgs) {
    for (let i = 0; i < uuids.length; i += 5) {
      const r = await kapi("/v1/api/talk/friends/message/default/send", token, { receiver_uuids: JSON.stringify(uuids.slice(i, i + 5)), template_object: m.tpl }).catch((e) => ({ error: e.message }));
      if ((r as any).error) fails.push((r as any).error); else for (const f of (r as any).failure_info || []) fails.push(`${f.code} ${f.msg}`);
    }
    if (cfg.sendToMe) await kapi("/v2/api/talk/memo/default/send", token, { template_object: m.tpl }).catch((e) => fails.push(e.message));
  }
  await admin.from("app_settings").upsert({ key: "kakao_notify", value: JSON.stringify({ ...cfg, lastSent: new Date().toISOString(), lastError: fails.join(" / ") || null }), updated_at: new Date().toISOString() });
  return { messages: msgs.map((m) => m.preview), sentTo: uuids.length, sendToMe: !!cfg.sendToMe, fails };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const action = body.action;
    // 매일 9시 — pg_cron 이 비밀값을 담아 호출
    if (action === "daily") {
      const sec = await cronSecret();
      if (!sec || req.headers.get("x-cron-secret") !== sec) return json({ error: "forbidden" }, 403);
      const { data: cfgRow } = await admin.from("app_settings").select("value").eq("key", "kakao_notify").maybeSingle();
      if (parseJSON(cfgRow?.value, {}).enabled === false) return json({ skipped: "꺼져 있음" });
      return json(await sendDigest());
    }
    const user = await staffUser(req);
    if (!user) return json({ error: "직원 로그인이 필요합니다" }, 401);

    if (action === "status") {
      const { data: s } = await admin.from("kakao_sender").select("nickname,connected_by,refresh_expires_at,updated_at").eq("id", 1).maybeSingle();
      return json({ sender: s || null, secretSet: !!Deno.env.get("KAKAO_CLIENT_SECRET"), cronSet: !!(await cronSecret()) });
    }
    if (action === "exchange") {
      const t = await kauth({ grant_type: "authorization_code", code: String(body.code || ""), redirect_uri: String(body.redirect_uri || "") });
      const me = await kapi("/v2/user/me", t.access_token);
      const nickname = me?.kakao_account?.profile?.nickname || me?.properties?.nickname || "카카오 사용자";
      await admin.from("kakao_members").upsert({ kakao_id: me.id, nickname, user_email: user.email, updated_at: new Date().toISOString() });
      const asSender = body.role === "sender" && user.email === ADMIN_EMAIL; // 보내는 계정은 관리자만 바꿀 수 있음
      if (asSender) {
        await admin.from("kakao_sender").upsert({
          id: 1, kakao_id: me.id, nickname, access_token: t.access_token, refresh_token: t.refresh_token,
          expires_at: later(t.expires_in), refresh_expires_at: later(t.refresh_token_expires_in), connected_by: user.email, updated_at: new Date().toISOString(),
        });
      }
      return json({ nickname, role: asSender ? "sender" : "member", scope: t.scope || "" });
    }
    if (action === "friends") {
      const token = await senderToken();
      const d = await kapi("/v1/api/talk/friends?limit=100", token);
      return json({ friends: (d.elements || []).map((f: any) => ({ uuid: f.uuid, nickname: f.profile_nickname, img: f.profile_thumbnail_image || "" })) });
    }
    if (action === "preview") return json({ messages: templates(await buildDigest()).map((m) => m.preview) });
    if (action === "test") return json(await sendDigest());
    return json({ error: "알 수 없는 요청" }, 400);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
