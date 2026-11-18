// Dugout · capa online sobre Supabase.
// Da a la web la misma interfaz de "salas" que usaba el prototipo (claude.use("room")),
// pero implementada con Supabase Realtime (presencia). También crea una cuenta anónima
// automáticamente para cada jugador y sincroniza su apodo.
(function () {
  const cfg = window.DUGOUT_CONFIG || {};
  let sb = null;
  try {
    if (window.supabase && cfg.supabaseUrl && cfg.supabaseKey) {
      sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey, {
        auth: { persistSession: true, autoRefreshToken: true },
        realtime: { params: { eventsPerSecond: 20 } }
      });
    }
  } catch (e) { console.warn("Supabase no disponible", e); }
  window.DG = { sb, user: null, profile: null, ready: null };

  // ---------- Cuenta anónima automática ----------
  DG.ready = (async () => {
    if (!sb) return null;
    try {
      let { data: { session } } = await sb.auth.getSession();
      if (!session) {
        const { data, error } = await sb.auth.signInAnonymously();
        if (error) throw error;
        session = data.session;
      }
      DG.user = session && session.user;
      if (DG.user) {
        const { data } = await sb.from("profiles").select("*").eq("id", DG.user.id).maybeSingle();
        DG.profile = data || null;
      }
      DG.status = DG.user ? "ok" : "sin cuenta";
      return DG.user;
    } catch (e) { console.warn("No se pudo iniciar sesión", e); DG.status = "error"; DG.error = (e && (e.message || e.msg)) || String(e); return null; }
  })();
  // Indicador de conexión en el pie de página
  DG.ready.then(() => {
    const el = document.getElementById("dg-status"); if (!el) return;
    if (!sb) el.textContent = "Servidor: no disponible (no se pudo cargar Supabase).";
    else if (DG.user) el.textContent = "Servidor: conectado ✓ (" + (DG.user.is_anonymous ? "cuenta anónima" : "cuenta") + ")";
    else el.textContent = "Servidor: sin cuenta — " + (DG.error || "error desconocido");
  });

  DG.setNick = async (nick) => {
    if (!sb || !DG.user) return;
    try { await sb.rpc("set_nick", { p_nick: nick }); } catch (e) { console.warn(e); }
  };

  // ---------- Salas en tiempo real (presencia) ----------
  const tabId = (crypto.randomUUID ? crypto.randomUUID() : String(Math.random())).replace(/-/g, "").slice(0, 16);
  const rooms = {};
  async function join(name) {
    if (!sb) throw { code: "not_permitted", message: "Sin conexión" };
    if (rooms[name]) return rooms[name];
    const ch = sb.channel("dg-" + name, { config: { presence: { key: tabId } } });
    let mine = {}, peers = Object.freeze([]), conn = false, pending = null;
    const handlers = new Set(), connHandlers = new Set();
    const rebuild = () => {
      const st = ch.presenceState();
      const arr = Object.entries(st).map(([k, metas]) => {
        const meta = metas[metas.length - 1] || {};
        const { presence_ref, ...rest } = meta;
        const isMe = k === tabId;
        return { peer: k, by: null, isMe, sameTab: isMe, kind: "viewer", guest: false,
                 presence: Object.freeze({ ...(isMe ? mine : rest) }), updatedAt: Date.now() };
      });
      if (!arr.some(p => p.sameTab)) arr.push({ peer: tabId, by: null, isMe: true, sameTab: true, kind: "viewer", guest: false, presence: Object.freeze({ ...mine }), updatedAt: Date.now() });
      peers = Object.freeze(arr);
      const change = { peers, joined: [], left: [], updated: [] };
      handlers.forEach(h => { try { h(change); } catch (e) { console.error(e); } });
    };
    ch.on("presence", { event: "sync" }, rebuild);
    await new Promise((res, rej) => {
      const t = setTimeout(() => rej({ code: "upstream_error", message: "Sin respuesta" }), 10000);
      ch.subscribe(status => {
        if (status === "SUBSCRIBED") { conn = true; clearTimeout(t); connHandlers.forEach(h => h(true)); res(); }
        else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") { conn = false; connHandlers.forEach(h => h(false)); }
      });
    });
    const api = {
      name,
      presence(patch) {
        for (const k in patch) { if (patch[k] === null) delete mine[k]; else mine[k] = patch[k]; }
        clearTimeout(pending);
        pending = setTimeout(() => { ch.track({ ...mine }).catch(() => {}); }, 50);
        rebuild();
        return Promise.resolve();
      },
      peers: () => peers,
      onPeers(h) { handlers.add(h); setTimeout(() => h({ peers, joined: peers, left: [], updated: [] })); return () => handlers.delete(h); },
      connected: () => conn,
      onConnection(h) { connHandlers.add(h); setTimeout(() => h(conn)); return () => connHandlers.delete(h); },
      emit() { return Promise.resolve(); },
      on() { return () => {}; },
      async leave() {
        delete rooms[name]; handlers.clear(); connHandlers.clear(); clearTimeout(pending);
        try { await ch.untrack(); } catch (e) {}
        try { await sb.removeChannel(ch); } catch (e) {}
      }
    };
    rooms[name] = api;
    return api;
  }
  const roomAPI = sb ? { join } : null;

  // Misma puerta de entrada que usaba el prototipo
  window.claude = { use: async (n) => (n === "room" ? roomAPI : null) };
})();
