// RuralTech — Design Tokens v2
// Expondo como globals para outros componentes Babel consumirem.

const RT = {
  // ── Cores ────────────────────────────────────────────────
  // Neutros quentes — brancos com leve tom terra
  bg:        'oklch(0.985 0.004 95)',       // branco quase-creme
  bgAlt:     'oklch(0.965 0.008 95)',       // painel
  bgSubtle:  'oklch(0.945 0.012 95)',       // fundo de seção
  ink:       'oklch(0.18 0.015 150)',       // preto esverdeado
  inkSoft:   'oklch(0.38 0.015 150)',
  inkMute:   'oklch(0.58 0.010 150)',
  hair:      'oklch(0.90 0.008 150)',       // bordas finas
  hairSoft:  'oklch(0.94 0.006 150)',

  // Primário — verde floresta (evoluído do 2F7D3D para algo mais profundo)
  primary:   'oklch(0.42 0.11 150)',
  primaryDeep: 'oklch(0.30 0.10 150)',
  primarySoft: 'oklch(0.94 0.04 150)',
  onPrimary: 'oklch(0.99 0.003 95)',

  // Accent terra — substitui o amarelo 0xFFE7A300 por algo mais premium
  accent:    'oklch(0.62 0.14 55)',         // terra queimada
  accentSoft:'oklch(0.93 0.05 70)',
  onAccent:  'oklch(0.99 0.003 95)',

  // Feedback
  ok:        'oklch(0.55 0.14 150)',
  okSoft:    'oklch(0.93 0.06 150)',
  warn:      'oklch(0.72 0.15 75)',
  warnSoft:  'oklch(0.94 0.07 85)',
  danger:    'oklch(0.55 0.19 25)',
  dangerSoft:'oklch(0.94 0.05 25)',
  info:      'oklch(0.55 0.12 230)',
  infoSoft:  'oklch(0.94 0.04 230)',

  // Mapa (dark thematic)
  mapBg:     'oklch(0.28 0.015 150)',
  mapLine:   'oklch(0.38 0.02 150)',
  mapInk:    'oklch(0.75 0.01 150)',

  // Raios
  r1: '6px', r2: '10px', r3: '14px', r4: '18px', r5: '24px', rFull: '999px',

  // Sombras
  sh1: '0 1px 2px rgba(20,30,25,.06), 0 1px 0 rgba(20,30,25,.04)',
  sh2: '0 4px 12px rgba(20,30,25,.08), 0 1px 2px rgba(20,30,25,.04)',
  sh3: '0 12px 32px rgba(20,30,25,.14), 0 2px 8px rgba(20,30,25,.06)',
  sh4: '0 24px 60px rgba(20,30,25,.22), 0 4px 12px rgba(20,30,25,.08)',

  // Type
  sans: '"Inter", system-ui, sans-serif',
  display: '"Inter Tight", "Inter", system-ui, sans-serif',
  mono: '"JetBrains Mono", ui-monospace, monospace',
};

// Shorthand iconografia — usamos lucide-like inline SVGs de uso geral
function Icon({ name, size = 20, color = 'currentColor', stroke = 1.75 }) {
  const s = size;
  const common = {
    width: s, height: s, viewBox: '0 0 24 24',
    fill: 'none', stroke: color, strokeWidth: stroke,
    strokeLinecap: 'round', strokeLinejoin: 'round',
  };
  const p = {
    // nav
    map:       <path d="M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3V6zM9 3v15M15 6v15"/>,
    bell:      <><path d="M6 8a6 6 0 1112 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10 21a2 2 0 104 0"/></>,
    user:      <><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-7 8-7s8 3 8 7"/></>,
    filter:    <path d="M3 5h18l-7 9v6l-4-2v-4L3 5z"/>,
    settings:  <><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 11-2.83 2.83l-.06-.06A1.65 1.65 0 0015 19.4a1.65 1.65 0 00-1 1.51V21a2 2 0 11-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 11-2.83-2.83l.06-.06A1.65 1.65 0 004.6 15a1.65 1.65 0 00-1.51-1H3a2 2 0 110-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 112.83-2.83l.06.06A1.65 1.65 0 009 4.6 1.65 1.65 0 0010 3.09V3a2 2 0 114 0v.09A1.65 1.65 0 0015 4.6a1.65 1.65 0 001.82-.33l.06-.06a2 2 0 112.83 2.83l-.06.06A1.65 1.65 0 0019.4 9c.1.24.16.5.16.77"/></>,
    // ops
    cow:       <><path d="M5 10c0-2 2-4 7-4s7 2 7 4v5a3 3 0 01-3 3h-8a3 3 0 01-3-3v-5z"/><path d="M3 9l2 1M21 9l-2 1M9 13v1M15 13v1"/></>,
    collar:    <><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 4v2M20 12h-2"/></>,
    gateway:   <><rect x="5" y="10" width="14" height="10" rx="1.5"/><path d="M7 14h2M11 14h2M7 17h6"/><path d="M8 10V6M16 10V6M8 3l8 3"/></>,
    polygon:   <path d="M12 3l8 5v8l-8 5-8-5V8l8-5z"/>,
    pin:       <><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 1116 0z"/><circle cx="12" cy="10" r="3"/></>,
    target:    <><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></>,
    compass:   <><circle cx="12" cy="12" r="9"/><path d="M15 9l-2 6-6 2 2-6 6-2z"/></>,
    layers:    <><path d="M12 3l9 5-9 5-9-5 9-5z"/><path d="M3 13l9 5 9-5M3 18l9 5 9-5"/></>,
    // status
    check:     <path d="M4 12l5 5L20 6"/>,
    alert:     <><path d="M12 3l10 17H2L12 3z"/><path d="M12 9v5M12 18v.5"/></>,
    battery:   <><rect x="2" y="7" width="18" height="10" rx="1.5"/><rect x="22" y="10" width="1" height="4"/><rect x="4" y="9" width="10" height="6"/></>,
    signal:    <><path d="M2 16h2v4H2zM7 12h2v8H7zM12 8h2v12h-2zM17 4h2v16h-2z"/></>,
    gps:       <><circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="9"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2"/></>,
    thermo:    <><path d="M10 14V5a2 2 0 114 0v9a4 4 0 11-4 0z"/><circle cx="12" cy="16" r="2"/></>,
    clock:     <><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
    // actions
    plus:      <path d="M12 5v14M5 12h14"/>,
    chev:      <path d="M9 6l6 6-6 6"/>,
    chevD:     <path d="M6 9l6 6 6-6"/>,
    chevL:     <path d="M15 6l-6 6 6 6"/>,
    close:     <path d="M6 6l12 12M6 18L18 6"/>,
    search:    <><circle cx="11" cy="11" r="7"/><path d="M21 21l-4-4"/></>,
    send:      <path d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/>,
    more:      <><circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/></>,
    undo:      <path d="M9 14l-4-4 4-4M5 10h9a5 5 0 010 10h-3"/>,
    erase:     <path d="M4 20h6l10-10-6-6L4 14v6zM8 20l10-10"/>,
    eye:       <><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></>,
    list:      <><path d="M8 6h13M8 12h13M8 18h13"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/></>,
    zap:       <path d="M13 2L3 14h7l-1 8 10-12h-7l1-8z"/>,
    lock:      <><rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 118 0v3"/></>,
    mail:      <><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/></>,
    logo:      <><path d="M4 20C4 12 8 4 12 4s8 8 8 16"/><path d="M4 20h16M8 14c1.5-1 3-1 4 0s2.5 1 4 0"/></>,
    arrowR:    <><path d="M5 12h14M13 5l7 7-7 7"/></>,
    arrowUp:   <><path d="M12 19V5M5 12l7-7 7 7"/></>,
    arrowDown: <><path d="M12 5v14M5 12l7 7 7-7"/></>,
    route:     <><circle cx="6" cy="19" r="3"/><circle cx="18" cy="5" r="3"/><path d="M9 19h4a4 4 0 004-4V9"/></>,
    clipboard: <><rect x="5" y="4" width="14" height="18" rx="2"/><rect x="9" y="2" width="6" height="4" rx="1"/><path d="M9 12h6M9 16h6"/></>,
    refresh:   <><path d="M3 12a9 9 0 0115-6.7L21 8M21 3v5h-5"/><path d="M21 12a9 9 0 01-15 6.7L3 16M3 21v-5h5"/></>,
    sliders:   <><path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h14M18 18h2"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="16" cy="18" r="2"/></>,
    add:       <><circle cx="12" cy="12" r="9"/><path d="M12 8v8M8 12h8"/></>,
    trash:     <><path d="M4 7h16M10 11v6M14 11v6"/><path d="M6 7l1 13a2 2 0 002 2h6a2 2 0 002-2l1-13M9 7V4a1 1 0 011-1h4a1 1 0 011 1v3"/></>,
    wifi:      <><path d="M2 9a15 15 0 0120 0M5 12a10 10 0 0114 0M8.5 15a5 5 0 017 0"/><circle cx="12" cy="19" r="1"/></>,
    bt:        <path d="M7 7l10 10-5 4V4l5 4L7 18"/>,
    crop:      <><path d="M6 2v16a2 2 0 002 2h14"/><path d="M2 6h16a2 2 0 012 2v14"/></>,
  }[name];
  return <svg {...common} style={{flexShrink: 0, display: 'block'}}>{p}</svg>;
}

window.RT = RT;
window.Icon = Icon;
