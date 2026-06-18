// RuralTech — Primitivos compartilhados

// ── Phone Frame (bezel moderno, tela 390×844 para densidade Android-like) ─
function Phone({ children, label, note, w = 390, h = 844, dark = false }) {
  return (
    <div style={{display: 'flex', flexDirection: 'column', gap: 14, alignItems: 'flex-start'}}>
      {label && (
        <div style={{display: 'flex', alignItems: 'baseline', gap: 10}}>
          <span style={{
            fontFamily: RT.mono, fontSize: 11, letterSpacing: '.08em',
            color: RT.inkMute, textTransform: 'uppercase',
          }}>{label}</span>
          {note && <span style={{fontSize: 12, color: RT.inkSoft}}>{note}</span>}
        </div>
      )}
      <div style={{
        width: w + 16, height: h + 16, padding: 8,
        background: 'linear-gradient(180deg, #2a2a28 0%, #1a1a18 100%)',
        borderRadius: 44, boxShadow: RT.sh4,
        position: 'relative',
      }}>
        <div style={{
          width: w, height: h, borderRadius: 36, overflow: 'hidden',
          background: dark ? RT.ink : RT.bg,
          position: 'relative',
          boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.04)',
        }}>
          {children}
        </div>
      </div>
    </div>
  );
}

// ── Status bar (Android-style, minimal) ─
function StatusBar({ dark = false, time = '14:32' }) {
  const c = dark ? 'rgba(255,255,255,.92)' : RT.ink;
  return (
    <div style={{
      height: 36, padding: '0 22px', display: 'flex', alignItems: 'center',
      justifyContent: 'space-between', fontFamily: RT.sans, fontSize: 14,
      fontWeight: 600, color: c, position: 'relative', zIndex: 5,
    }}>
      <span style={{fontVariantNumeric: 'tabular-nums'}}>{time}</span>
      <div style={{display: 'flex', alignItems: 'center', gap: 6}}>
        <svg width="15" height="11" viewBox="0 0 15 11"><path d="M1 7l2-1v4H1V7zm4-2l2-1v6H5V5zm4-2l2-1v8H9V3zm4-2l2-1v10h-2V1z" fill={c}/></svg>
        <svg width="15" height="11" viewBox="0 0 15 11"><path d="M7.5 2a6.5 6.5 0 016 4l-1 .5a5.5 5.5 0 00-10 0L1.5 6a6.5 6.5 0 016-4zm0 3a3.5 3.5 0 013.2 2l-1 .5a2.5 2.5 0 00-4.4 0l-1-.5A3.5 3.5 0 017.5 5zm0 3a1.5 1.5 0 11-.01 3 1.5 1.5 0 01.01-3z" fill={c}/></svg>
        <div style={{
          width: 24, height: 11, border: `1.2px solid ${c}`, borderRadius: 3,
          padding: 1.5, position: 'relative',
        }}>
          <div style={{width: '78%', height: '100%', background: c, borderRadius: 1}}/>
          <div style={{position: 'absolute', right: -3, top: 3, width: 2, height: 5, background: c, borderRadius: 1}}/>
        </div>
      </div>
    </div>
  );
}

// ── Nav bar (gesture pill) ─
function NavPill({ dark = false, overlay = false }) {
  return (
    <div style={{
      position: overlay ? 'absolute' : 'relative',
      left: 0, right: 0, bottom: 0,
      height: 28, display: 'flex', alignItems: 'flex-start', justifyContent: 'center',
      paddingTop: 8, zIndex: 6, pointerEvents: 'none',
    }}>
      <div style={{
        width: 130, height: 4, borderRadius: 4,
        background: dark ? 'rgba(255,255,255,.8)' : RT.ink, opacity: .85,
      }}/>
    </div>
  );
}

// ── Botões ─
function Btn({ children, variant = 'primary', size = 'md', block = false, icon, trailing, style = {} }) {
  const sizes = {
    sm: { h: 36, px: 14, fs: 13, rad: RT.r2 },
    md: { h: 48, px: 18, fs: 15, rad: RT.r3 },
    lg: { h: 56, px: 22, fs: 16, rad: RT.r3 },
  }[size];
  const variants = {
    primary: { bg: RT.primary, color: RT.onPrimary, border: 'none' },
    primaryDeep: { bg: RT.primaryDeep, color: RT.onPrimary, border: 'none' },
    accent: { bg: RT.accent, color: RT.onAccent, border: 'none' },
    danger: { bg: RT.danger, color: '#fff', border: 'none' },
    ghost: { bg: 'transparent', color: RT.ink, border: `1px solid ${RT.hair}` },
    solid: { bg: RT.ink, color: RT.bg, border: 'none' },
    tonal: { bg: RT.primarySoft, color: RT.primaryDeep, border: 'none' },
  }[variant];
  return (
    <button style={{
      height: sizes.h, padding: `0 ${sizes.px}px`, borderRadius: sizes.rad,
      background: variants.bg, color: variants.color, border: variants.border,
      fontFamily: RT.sans, fontSize: sizes.fs, fontWeight: 600,
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      width: block ? '100%' : 'auto', cursor: 'pointer', letterSpacing: '-.005em',
      ...style,
    }}>
      {icon && <Icon name={icon} size={sizes.fs + 3} stroke={2}/>}
      {children}
      {trailing && <Icon name={trailing} size={sizes.fs + 3} stroke={2}/>}
    </button>
  );
}

// ── Chip ─
function Chip({ children, active = false, icon, dot, onClick, style = {} }) {
  return (
    <div onClick={onClick} style={{
      height: 32, padding: '0 12px', borderRadius: RT.rFull,
      background: active ? RT.ink : RT.bg,
      color: active ? RT.bg : RT.ink,
      border: `1px solid ${active ? RT.ink : RT.hair}`,
      display: 'inline-flex', alignItems: 'center', gap: 6,
      fontFamily: RT.sans, fontSize: 13, fontWeight: 500,
      whiteSpace: 'nowrap', cursor: 'pointer', ...style,
    }}>
      {dot && <span style={{width: 6, height: 6, borderRadius: '50%', background: dot}}/>}
      {icon && <Icon name={icon} size={14} stroke={2}/>}
      {children}
    </div>
  );
}

// ── Badge ─
function Badge({ children, tone = 'neutral', style = {} }) {
  const tones = {
    neutral: { bg: RT.hairSoft, fg: RT.inkSoft },
    ok:      { bg: RT.okSoft, fg: RT.ok },
    warn:    { bg: RT.warnSoft, fg: 'oklch(.45 .15 75)' },
    danger:  { bg: RT.dangerSoft, fg: RT.danger },
    info:    { bg: RT.infoSoft, fg: RT.info },
    primary: { bg: RT.primarySoft, fg: RT.primaryDeep },
    accent:  { bg: RT.accentSoft, fg: 'oklch(.38 .14 55)' },
  }[tone];
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: '3px 8px', borderRadius: RT.rFull,
      background: tones.bg, color: tones.fg,
      fontFamily: RT.sans, fontSize: 11, fontWeight: 600,
      letterSpacing: '.02em', ...style,
    }}>{children}</span>
  );
}

// ── Card / Sheet ─
function Card({ children, pad = 16, style = {} }) {
  return (
    <div style={{
      background: RT.bg, border: `1px solid ${RT.hair}`, borderRadius: RT.r3,
      padding: pad, boxShadow: RT.sh1, ...style,
    }}>{children}</div>
  );
}

// ── Input ─
function Field({ label, value, placeholder, icon, type = 'text', trailing, hint, error, style = {} }) {
  return (
    <div style={{display: 'flex', flexDirection: 'column', gap: 6, ...style}}>
      {label && (
        <label style={{
          fontFamily: RT.sans, fontSize: 13, fontWeight: 500,
          color: RT.inkSoft, letterSpacing: '-.005em',
        }}>{label}</label>
      )}
      <div style={{
        height: 52, padding: '0 14px', borderRadius: RT.r3,
        background: RT.bgAlt, border: `1px solid ${error ? RT.danger : RT.hair}`,
        display: 'flex', alignItems: 'center', gap: 10,
      }}>
        {icon && <Icon name={icon} size={18} color={RT.inkMute}/>}
        <input
          type={type} defaultValue={value} placeholder={placeholder}
          style={{
            flex: 1, border: 'none', outline: 'none', background: 'transparent',
            fontFamily: type === 'mono' ? RT.mono : RT.sans, fontSize: 15,
            color: RT.ink,
          }}
          readOnly
        />
        {trailing && <Icon name={trailing} size={18} color={RT.inkMute}/>}
      </div>
      {hint && <span style={{fontSize: 12, color: error ? RT.danger : RT.inkMute}}>{hint}</span>}
    </div>
  );
}

// ── FAB ─
function Fab({ icon = 'plus', extended, label, style = {} }) {
  return (
    <button style={{
      height: 56, minWidth: 56, padding: extended ? '0 20px 0 16px' : 0,
      borderRadius: extended ? RT.rFull : 16,
      background: RT.primary, color: RT.onPrimary, border: 'none',
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 10,
      boxShadow: RT.sh3, fontFamily: RT.sans, fontSize: 15, fontWeight: 600,
      cursor: 'pointer', ...style,
    }}>
      <Icon name={icon} size={22} stroke={2}/>
      {extended && label}
    </button>
  );
}

// ── Bottom Tab Bar ─
function TabBar({ active = 'map', onTab }) {
  const tabs = [
    { id: 'map', label: 'Mapa', icon: 'map' },
    { id: 'events', label: 'Eventos', icon: 'bell' },
    { id: 'ops', label: 'Operações', icon: 'route' },
    { id: 'profile', label: 'Perfil', icon: 'user' },
  ];
  return (
    <div style={{
      height: 72, background: RT.bg,
      borderTop: `1px solid ${RT.hair}`,
      display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
      paddingBottom: 4,
    }}>
      {tabs.map(t => {
        const a = active === t.id;
        return (
          <button key={t.id} style={{
            background: 'transparent', border: 'none',
            display: 'flex', flexDirection: 'column', alignItems: 'center',
            justifyContent: 'center', gap: 4, cursor: 'pointer',
            color: a ? RT.primaryDeep : RT.inkMute,
          }}>
            <div style={{
              width: 56, height: 28, borderRadius: RT.rFull,
              background: a ? RT.primarySoft : 'transparent',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icon name={t.icon} size={22} stroke={a ? 2.2 : 1.8}/>
            </div>
            <span style={{
              fontFamily: RT.sans, fontSize: 11, fontWeight: a ? 700 : 500,
              letterSpacing: '-.005em',
            }}>{t.label}</span>
          </button>
        );
      })}
    </div>
  );
}

// ── AppBar ─
function AppBar({ title, subtitle, leading = 'chevL', trailing, variant = 'plain' }) {
  const bg = variant === 'solid' ? RT.ink : variant === 'primary' ? RT.primaryDeep : 'transparent';
  const fg = (variant === 'solid' || variant === 'primary') ? RT.bg : RT.ink;
  const fgMute = (variant === 'solid' || variant === 'primary') ? 'rgba(255,255,255,.6)' : RT.inkMute;
  return (
    <div style={{
      height: 56, padding: '0 8px 0 8px', background: bg,
      display: 'flex', alignItems: 'center', gap: 4,
      borderBottom: variant === 'plain' ? `1px solid ${RT.hair}` : 'none',
    }}>
      {leading && (
        <button style={{
          width: 44, height: 44, borderRadius: RT.rFull, border: 'none',
          background: 'transparent', color: fg, display: 'flex',
          alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
        }}>
          <Icon name={leading} size={22} color={fg} stroke={2}/>
        </button>
      )}
      <div style={{flex: 1, display: 'flex', flexDirection: 'column', padding: '0 4px'}}>
        <div style={{
          fontFamily: RT.display, fontSize: 17, fontWeight: 600, color: fg,
          letterSpacing: '-.02em', lineHeight: 1.1,
        }}>{title}</div>
        {subtitle && (
          <div style={{fontFamily: RT.sans, fontSize: 12, color: fgMute, lineHeight: 1.2}}>{subtitle}</div>
        )}
      </div>
      {trailing && (
        <div style={{display: 'flex', alignItems: 'center', gap: 2, paddingRight: 4}}>
          {trailing.map((t, i) => (
            <button key={i} style={{
              width: 44, height: 44, borderRadius: RT.rFull, border: 'none',
              background: 'transparent', color: fg, display: 'flex',
              alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
              position: 'relative',
            }}>
              <Icon name={t.icon} size={22} color={fg} stroke={1.8}/>
              {t.badge && <span style={{
                position: 'absolute', top: 8, right: 8, width: 8, height: 8,
                borderRadius: '50%', background: RT.accent,
                border: `2px solid ${bg === 'transparent' ? RT.bg : bg}`,
              }}/>}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Map Canvas (fake map with tiles, polygons, markers) ─
function MapCanvas({ children, style = {}, variant = 'day' }) {
  const dark = variant === 'night';
  return (
    <div style={{
      position: 'absolute', inset: 0, overflow: 'hidden',
      background: dark ? RT.mapBg : 'oklch(.91 .015 120)',
      ...style,
    }}>
      {/* fake terrain */}
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice">
        <defs>
          <pattern id="contour" x="0" y="0" width="60" height="60" patternUnits="userSpaceOnUse">
            <path d="M0 30 Q15 20 30 30 T60 30" stroke={dark ? 'rgba(255,255,255,.06)' : 'rgba(60,80,50,.08)'} fill="none"/>
            <path d="M0 15 Q15 5 30 15 T60 15" stroke={dark ? 'rgba(255,255,255,.04)' : 'rgba(60,80,50,.05)'} fill="none"/>
            <path d="M0 45 Q15 35 30 45 T60 45" stroke={dark ? 'rgba(255,255,255,.04)' : 'rgba(60,80,50,.05)'} fill="none"/>
          </pattern>
          <linearGradient id="terrain" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor={dark ? 'oklch(.26 .015 150)' : 'oklch(.90 .02 120)'}/>
            <stop offset=".5" stopColor={dark ? 'oklch(.30 .018 145)' : 'oklch(.93 .022 115)'}/>
            <stop offset="1" stopColor={dark ? 'oklch(.24 .015 155)' : 'oklch(.88 .025 110)'}/>
          </linearGradient>
        </defs>
        <rect width="390" height="844" fill="url(#terrain)"/>
        <rect width="390" height="844" fill="url(#contour)"/>
        {/* rivers */}
        <path d="M-20 280 Q 100 260 180 320 T 410 380" stroke={dark ? 'oklch(.45 .05 220)' : 'oklch(.78 .06 220)'} strokeWidth="14" fill="none" opacity=".8"/>
        <path d="M-20 280 Q 100 260 180 320 T 410 380" stroke={dark ? 'oklch(.55 .08 220)' : 'oklch(.85 .08 215)'} strokeWidth="6" fill="none" opacity=".9"/>
        {/* roads */}
        <path d="M50 0 Q 80 200 200 400 T 340 844" stroke={dark ? 'oklch(.45 .008 100)' : 'oklch(.7 .02 90)'} strokeWidth="2" fill="none" opacity=".6" strokeDasharray="2 4"/>
        <path d="M0 600 L 390 560" stroke={dark ? 'oklch(.48 .01 100)' : 'oklch(.75 .02 90)'} strokeWidth="3" fill="none" opacity=".7"/>
        {/* forest patches */}
        <ellipse cx="80" cy="150" rx="60" ry="40" fill={dark ? 'oklch(.22 .04 150)' : 'oklch(.80 .05 145)'} opacity=".6"/>
        <ellipse cx="310" cy="700" rx="90" ry="60" fill={dark ? 'oklch(.22 .04 150)' : 'oklch(.80 .05 145)'} opacity=".6"/>
      </svg>
      {children}
    </div>
  );
}

Object.assign(window, {
  Phone, StatusBar, NavPill, Btn, Chip, Badge, Card, Field, Fab, TabBar, AppBar, MapCanvas,
});
