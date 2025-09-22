javascript: (() => {
    const meta = document.querySelector('meta[name="req-id"]');
    const req = (meta && meta.content) || "noid";
    const now = new Date();
    const ts = now.toISOString().replace(/[-:]/g, "").replace(/\..+/, "");
    const ls = (k) => localStorage.getItem(k) || "";
    const sv = (k, v) => localStorage.setItem(k, v);
    const m = prompt("Module?", ls("ERNST_module") || "");
    if (m === null) return;
    sv("ERNST_module", m);
    const s = prompt("Screen?", ls("ERNST_screen") || "");
    if (s === null) return;
    sv("ERNST_screen", s);
    const v = prompt("View?", ls("ERNST_view") || "");
    if (v === null) return;
    sv("ERNST_view", v);
    const safe = (t) =>
        String(t)
            .trim()
            .replace(/\s+/g, "_")
            .replace(/[^A-Za-z0-9_\-äöüÄÖÜß]/g, "");
    const fn = `${ts}_${safe(m)}_${safe(s)}_${safe(v)}_${req}.png`;
    navigator.clipboard
        .writeText(fn)
        .then(() => alert("Filename in Clipboard:\\n" + fn))
        .catch(() => prompt("Copy filename:", fn));
})();
